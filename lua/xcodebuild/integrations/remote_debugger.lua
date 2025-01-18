---@mod xcodebuild.integrations.remote_debugger Remote Debugger Integration
---@brief [[
---This module is responsible for the integration of `phymobiledevice3`
---debug session with `nvim-dap`. It enables debugging on physical devices.
---
---The module listens to `nvim-dap` events and starts the remote debugger.
---
---See |xcodebuild.requirements|
---
---@brief ]]

--- 1 - Legacy mode (iOS <17)
--- 2 - Secured mode (iOS 17+)
---@alias RemoteDebuggerMode number
---| 1 # Legacy mode
---| 2 # Secured mode

local notifications = require("xcodebuild.broadcasting.notifications")
local util = require("xcodebuild.util")
local projectConfig = require("xcodebuild.project.config")
local deviceProxy = require("xcodebuild.platform.device_proxy")

local M = {}

local PLUGIN_ID = "xcodebuild-remote-debugger"

M.LEGACY_MODE = 1
M.SECURED_MODE = 2

---The current mode of the remote debugger.
---@type RemoteDebuggerMode
M.mode = M.SECURED_MODE

---Updates logs in the DAP console.
---@param lines string[]
local function update_console(lines)
  require("xcodebuild.integrations.dap").update_console(lines)
end

---Removes the listeners.
local function remove_listeners()
  local listeners = require("dap").listeners.after

  listeners.event_terminated[PLUGIN_ID] = nil
  listeners.event_continued[PLUGIN_ID] = nil
  listeners.event_output[PLUGIN_ID] = nil
  listeners.disconnect[PLUGIN_ID] = nil
end

---Sets up the listeners to observe when the debug session is terminated.
---WARNING: They are not always triggered ¯\_(ツ)_/¯
---
---When the even is received, it stops the remote debugger
---and removes the listeners.
local function setup_terminate_listeners()
  local listeners = require("dap").listeners.after

  listeners.event_terminated[PLUGIN_ID] = function()
    remove_listeners()
    M.stop_remote_debugger()
  end

  listeners.disconnect[PLUGIN_ID] = function()
    remove_listeners()
    M.stop_remote_debugger()
  end
end

---Sets up the listeners to observe the connection with the remote debugger.
---When the connection is established, it sends a notification.
---When the output is received, it appends the logs to the file and too
---the DAP console.
local function setup_connection_listeners()
  local appdata = require("xcodebuild.project.appdata")
  local listeners = require("dap").listeners.after
  local processLaunched = false
  local buffer = ""

  listeners.event_continued[PLUGIN_ID] = function()
    listeners.event_continued[PLUGIN_ID] = nil
    notifications.send("Remote debugger connected")
  end

  listeners.event_output[PLUGIN_ID] = function(_, body)
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

---Starts `nvim-dap` debug session. It connects to `codelldb`.
---@param opts {attach: boolean}|nil
local function start_dap(opts)
  opts = opts or {}

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

  local appdata = require("xcodebuild.project.appdata")

  dap.run({
    env = appdata.read_env_vars(),
    args = appdata.read_run_args(),
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
          notifications.send_error("Failed to find the app path on the device.")
          return "platform status"
        end

        update_console({ "App path: " .. appPath })

        return "script lldb.target.module[0].SetPlatformFileSpec(lldb.SBFileSpec('" .. appPath .. "'))"
      end,

      function()
        if M.mode == M.LEGACY_MODE then
          return M.connection_string
        else
          return deviceProxy.start_secure_server(projectConfig.settings.destination, M.rsd_param)
        end
      end,

      function()
        if opts.attach then
          local pid = deviceProxy.find_app_pid(projectConfig.settings.productName)
          if not pid or pid == "" then
            notifications.send_error("Failed to find the app PID on the device.")
            return "platform status"
          end
          update_console({ "App PID: " .. pid })

          return "process attach --pid " .. pid
        else
          return "process launch"
        end
      end,

      function()
        update_console({ "" })
        return opts.attach and "continue" or "process status"
      end,
    },
  })
end

---Sets the mode of the remote debugger.
---Use `M.LEGACY_MODE` or `M.SECURED_MODE`.
---@param mode RemoteDebuggerMode
function M.set_mode(mode)
  M.mode = mode
end

---Starts legacy server without trusted channel.
---After the server is started, it starts the debug session.
---@param opts {attach: boolean}|nil
---@param callback function|nil
local function start_legacy_server(opts, callback)
  local config = require("xcodebuild.core.config")

  M.debug_server_job = deviceProxy.start_server(
    projectConfig.settings.destination,
    config.options.integrations.pymobiledevice.remote_debugger_port,
    function(connection_string)
      M.connection_string = connection_string

      update_console({
        "Connecting to " .. connection_string:gsub("process connect connect://", ""),
      })
      setup_terminate_listeners()
      start_dap(opts)

      util.call(callback)
    end
  )
end

---Starts secured tunnel with trusted channel.
---After the tunnel is established, it starts the debug session.
---@param opts {attach: boolean}|nil
---@param callback function|nil
local function start_secured_tunnel(opts, callback)
  M.debug_server_job = deviceProxy.create_secure_tunnel(projectConfig.settings.destination, function(rsdParam)
    M.rsd_param = rsdParam

    update_console({ "Connecting to " .. rsdParam:gsub("%-%-rsd ", "") })
    setup_terminate_listeners()
    start_dap(opts)

    util.call(callback)
  end)
end

---Starts the remote debugger based on the mode.
---@param opts {attach: boolean}|nil
---@param callback function|nil
function M.start_remote_debugger(opts, callback)
  if not deviceProxy.validate_installation() then
    return
  end

  M.stop_remote_debugger()

  notifications.send("Starting remote debugger...")
  require("xcodebuild.project.appdata").clear_app_logs()

  if M.mode == M.LEGACY_MODE then
    start_legacy_server(opts, callback)
  else
    start_secured_tunnel(opts, callback)
  end
end

---Stops the remote debugger based on the mode.
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
