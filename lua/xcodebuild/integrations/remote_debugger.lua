local notifications = require("xcodebuild.broadcasting.notifications")
local util = require("xcodebuild.util")
local projectConfig = require("xcodebuild.project.config")
local appdata = require("xcodebuild.project.appdata")
local config = require("xcodebuild.core.config")
local deviceProxy = require("xcodebuild.platform.device_proxy")

local M = {}

M.LEGACY_MODE = 1
M.SECURED_MODE = 2

M.mode = M.SECURED_MODE

local function remove_listeners()
  local listeners = require("dap").listeners.after

  listeners.event_terminated["xcodebuild"] = nil
  listeners.event_continued["xcodebuild"] = nil
  listeners.event_output["xcodebuild"] = nil
  listeners.disconnect["xcodebuild"] = nil
end

local function setup_terminate_listeners()
  local listeners = require("dap").listeners.after

  listeners.event_terminated["xcodebuild"] = function()
    remove_listeners()
    M.stop_remote_debugger()
  end

  listeners.disconnect["xcodebuild"] = function()
    remove_listeners()
    M.stop_remote_debugger()
  end
end

local function setup_connection_listeners()
  local listeners = require("dap").listeners.after
  local processLaunched = false
  local buffer = ""

  listeners.event_continued["xcodebuild"] = function()
    listeners.event_continued["xcodebuild"] = nil
    notifications.send("Remote debugger connected")
  end

  listeners.event_output["xcodebuild"] = function(_, body)
    if not processLaunched and string.find(body.output, "Launched process") then
      processLaunched = true
      return
    end

    if processLaunched then
      local splitted = vim.split(body.output, "\n", { plain = true })

      -- the last line can only be empty or non empty when it's partial output
      splitted[1] = buffer .. splitted[1]
      buffer = splitted[#splitted]
      table.remove(splitted, #splitted)

      appdata.append_app_logs(splitted)
    end
  end
end

function M.set_mode(mode)
  M.mode = mode
end

function M.start_dap()
  local success, dap = pcall(require, "dap")
  if not success then
    error("xcodebuild.nvim: Could not load nvim-dap plugin")
    return
  end

  if not deviceProxy.validate_installation() then
    return
  end

  notifications.send("Connecting to device...")
  setup_connection_listeners()

  dap.run({
    name = "iOS Remote Debugger",
    type = "codelldb",
    request = "launch",
    cwd = "${workspaceFolder}",
    stopOnEntry = false,
    waitFor = true,
    initCommands = {
      "platform select remote-ios",
    },
    targetCreateCommands = {
      function()
        return "target create '" .. projectConfig.settings.appPath .. "'"
      end,
    },
    processCreateCommands = {
      function()
        local appPath =
          deviceProxy.find_app_path(projectConfig.settings.destination, projectConfig.settings.bundleId)

        if not appPath then
          error("xcodebuild.nvim: Failed to find the app path on the device.")
          return nil
        end

        require("xcodebuild.dap").update_console({ "App path: " .. appPath, "" })

        return "script lldb.target.module[0].SetPlatformFileSpec(lldb.SBFileSpec('" .. appPath .. "'))"
      end,

      function()
        if M.mode == M.LEGACY_MODE then
          return M.connection_string
        else
          return deviceProxy.start_secure_server(projectConfig.settings.destination, M.rsd_param)
        end
      end,

      "process launch",
    },
  })
end

local function start_legacy_server(callback)
  local xcodebuildDap = require("xcodebuild.dap")

  M.debug_server_job = deviceProxy.start_server(
    projectConfig.settings.destination,
    config.options.commands.remote_debugger_port,
    function(connection_string)
      M.connection_string = connection_string

      xcodebuildDap.update_console({
        "Connecting to " .. connection_string:gsub("process connect connect://", ""),
      })
      setup_terminate_listeners()
      xcodebuildDap.start_dap_in_swift_buffer(true)

      util.call(callback)
    end
  )
end

local function start_secured_tunnel(callback)
  local xcodebuildDap = require("xcodebuild.dap")

  M.debug_server_job = deviceProxy.create_secure_tunnel(projectConfig.settings.destination, function(rsdParam)
    M.rsd_param = rsdParam

    xcodebuildDap.update_console({ "Connecting to " .. rsdParam:gsub("%-%-rsd ", "") })
    setup_terminate_listeners()
    xcodebuildDap.start_dap_in_swift_buffer(true)

    util.call(callback)
  end)
end

function M.start_remote_debugger(callback)
  if not deviceProxy.validate_installation() then
    return
  end

  local xcodebuildDap = require("xcodebuild.dap")
  M.stop_remote_debugger()

  notifications.send("Starting remote debugger...")
  xcodebuildDap.clear_console()

  if M.mode == M.LEGACY_MODE then
    start_legacy_server(callback)
  else
    start_secured_tunnel(callback)
  end
end

function M.stop_remote_debugger()
  if not M.debug_server_job then
    if M.mode == M.SECURED_MODE then
      deviceProxy.close_secure_tunnel()
    end
    return
  end

  if M.mode == M.LEGACY_MODE then
    vim.fn.jobstop(M.debug_server_job)
  else
    deviceProxy.close_secure_tunnel()
  end

  M.debug_server_job = nil
  M.rsd_param = nil
  M.connection_string = nil

  notifications.send("Remote debugger stopped")
end

return M
