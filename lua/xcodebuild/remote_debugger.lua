local notifications = require("xcodebuild.notifications")
local util = require("xcodebuild.util")
local projectConfig = require("xcodebuild.project_config")
local appdata = require("xcodebuild.appdata")
local config = require("xcodebuild.config")

local M = {}

local function get_tool_path()
  return config.options.commands.remote_debugger or appdata.tool_path(REMOTE_DEBUGGER_TOOL)
end

local function kill_remote_debugger()
  util.shell("sudo '" .. get_tool_path() .. "' kill 2>/dev/null")
end

local function remove_listeners()
  local listeners = require("dap").listeners.after

  listeners.event_terminated["xcodebuild"] = nil
  listeners.disconnect["xcodebuild"] = nil
  listeners.event_continued["xcodebuild"] = nil
  listeners.event_output["xcodebuild"] = nil
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

local function wait_for_rsd_param_and_start_dap(callback)
  local xcodebuildDap = require("xcodebuild.dap")

  return function(_, data, _)
    if M.rsd_param then
      return
    end

    for _, line in ipairs(data) do
      local rsd = string.match(line, "(%-%-rsd [^%s]+ %d+)")
      if rsd then
        notifications.send("Remote debugger started")
        M.rsd_param = rsd

        xcodebuildDap.update_console({ "Connecting to " .. rsd:gsub("%-%-rsd ", "") })

        setup_terminate_listeners()
        xcodebuildDap.start_dap_in_swift_buffer(true)
        util.call(callback)

        return
      end
    end
  end
end

local function check_if_device_disconnected()
  M.deviceDisconnected = false

  return function(_, data, _)
    if M.deviceDisconnected then
      return
    end

    for _, line in ipairs(data) do
      if string.find(line, "Device is not connected") then
        M.deviceDisconnected = true
      end
    end
  end
end

local function process_remote_debugger_exit()
  return function(_, code, _)
    if M.deviceDisconnected then
      notifications.send_error("Device is not connected")
    elseif code == 1 then
      notifications.send_error(
        "Failed to start remote debugger. Make sure that you added the remote_debugger tool to sudoers file."
      )
      notifications.send_error(
        "You can do this by running `sudo visudo -f /etc/sudoers` and adding the following line:\n"
          .. vim.fn.expand("$USER")
          .. " ALL = (ALL) NOPASSWD: "
          .. get_tool_path()
      )
    elseif code ~= 0 and code ~= 143 and code ~= 137 and M.debug_server_job then
      notifications.send_error("Failed to start remote debugger (code: " .. code .. ")")
    end
  end
end

function M.validate_required_tools()
  if vim.fn.executable("pymobiledevice3") == 0 then
    notifications.send_error(
      "pymobiledevice3 tool not found. Please run `python3 -m pip install -U pymobiledevice3` to install it."
    )
    return false
  end

  if vim.fn.executable("jq") == 0 then
    notifications.send_error("jq tool not found. Please run `brew install jq` to install it.")
    return false
  end

  return true
end

function M.start_dap()
  local success, dap = pcall(require, "dap")
  if not success then
    error("xcodebuild.nvim: Could not load nvim-dap plugin")
    return
  end

  if not M.validate_required_tools() then
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
        local appPath = util.shell(
          "pymobiledevice3 apps list --no-color | jq -r '.\"" .. projectConfig.settings.bundleId .. "\".Path'"
        )[1]

        if not appPath then
          error("xcodebuild.nvim: Failed to find the app path on the device.")
          return nil
        end

        require("xcodebuild.dap").update_console({ "App path: " .. appPath, "" })

        return "script lldb.target.module[0].SetPlatformFileSpec(lldb.SBFileSpec('" .. appPath .. "'))"
      end,

      function()
        local instruction =
          util.shell("pymobiledevice3 developer debugserver start-server " .. M.rsd_param .. " --no-color")

        for _, line in ipairs(instruction) do
          local cmd = string.match(line, "%(lldb%) (process connect .*%d)%s+%<")
          if cmd then
            return cmd
          end
        end

        error(
          "xcodebuild.nvim: Failed to start debugger. Could not find the command to connect to the device."
        )
        return nil
      end,
      "process launch",
    },
  })
end

function M.start_remote_debugger(callback)
  if not M.validate_required_tools() then
    return
  end

  M.stop_remote_debugger()

  notifications.send("Starting remote debugger...")
  require("xcodebuild.dap").clear_console()

  local cmd = "sudo '" .. get_tool_path() .. "' start " .. projectConfig.settings.destination

  M.debug_server_job = vim.fn.jobstart(cmd, {
    stdout_buffered = false,
    stderr_buffered = false,
    on_stderr = check_if_device_disconnected(),
    on_stdout = wait_for_rsd_param_and_start_dap(callback),
    on_exit = process_remote_debugger_exit(),
  })
end

function M.stop_remote_debugger()
  if not M.debug_server_job then
    kill_remote_debugger()
    return
  end

  M.rsd_param = nil
  M.debug_server_job = nil

  kill_remote_debugger()
  notifications.send("Remote debugger stopped")
end

return M
