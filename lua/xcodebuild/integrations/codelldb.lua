---@mod xcodebuild.integrations.codelldb DAP Configurations - codelldb
---@tag xcodebuild.codelldb
---@brief [[
---This module contains DAP configurations for `codelldb` DAP server.
---@brief ]]

---@type DebuggerIntegration
local M = {
  get_macos_configuration = function()
    return {}
  end,
  get_ios_configuration = function()
    return {}
  end,
  get_remote_device_configuration = function(_)
    return {}
  end,
  get_adapter_name = function()
    return ""
  end,
  get_adapter = function()
    return {}
  end,
}

local appdata = require("xcodebuild.project.appdata")
local projectConfig = require("xcodebuild.project.config")
local config = require("xcodebuild.core.config").options.integrations.codelldb
local notifications = require("xcodebuild.broadcasting.notifications")

---Returns path to the built application.
---@return string
local function get_program_path()
  return projectConfig.settings.appPath
end

---Returns iOS configuration for `nvim-dap`.
---@return table
function M.get_ios_configuration()
  return {
    name = "iOS App Debugger",
    type = M.get_adapter_name(),
    request = "attach",
    cwd = vim.fn.getcwd(),
    stopOnEntry = false,
    waitFor = true,
    program = get_program_path,
  }
end

---Returns macOS configuration for `nvim-dap`.
---@return table
function M.get_macos_configuration()
  return {
    name = "macOS App Debugger",
    type = M.get_adapter_name(),
    args = appdata.read_run_args(),
    env = appdata.read_env_vars(),
    request = "launch",
    cwd = vim.fn.getcwd(),
    stopOnEntry = false,
    waitFor = true,
    program = get_program_path,
  }
end

---Returns remote debugging configuration for `nvim-dap`.
---@param request string "launch"|"attach"
---@return table
function M.get_remote_device_configuration(request)
  local deviceProxy = require("xcodebuild.platform.device_proxy")
  local remoteDebugger = require("xcodebuild.integrations.remote_debugger")
  local dapConfig = {
    name = "iOS Remote Debugger",
    type = M.get_adapter_name(),
    env = appdata.read_env_vars(),
    args = appdata.read_run_args(),
    request = request,
    cwd = vim.fn.getcwd(),
    stopOnEntry = false,
    waitFor = true,
    program = get_program_path,
  }

  dapConfig.initCommands = { "platform select remote-ios" }
  dapConfig.targetCreateCommands = {
    function()
      return "target create '" .. projectConfig.settings.appPath .. "'"
    end,
  }
  dapConfig.processCreateCommands = {
    function()
      local appPath =
        deviceProxy.find_app_path(projectConfig.settings.destination, projectConfig.settings.bundleId)

      if not appPath then
        notifications.send_error("Failed to find the app path on the device.")
        return "platform status"
      end

      appdata.append_app_logs({ "App path: " .. appPath })

      return "script lldb.target.module[0].SetPlatformFileSpec(lldb.SBFileSpec('" .. appPath .. "'))"
    end,

    function()
      if remoteDebugger.mode == remoteDebugger.LEGACY_MODE then
        return remoteDebugger.connection_string
      else
        return deviceProxy.start_secure_server(projectConfig.settings.destination, remoteDebugger.rsd_param)
      end
    end,

    function()
      if request == "attach" then
        local pid = deviceProxy.find_app_pid(projectConfig.settings.productName)
        if not pid or pid == "" then
          notifications.send_error("Failed to find the app PID on the device.")
          return "platform status"
        end
        appdata.append_app_logs({ "App PID: " .. pid })

        return "process attach -c --pid " .. pid
      else
        return "process launch"
      end
    end,
  }

  return dapConfig
end

---Returns the name of the adapter.
---@return string
function M.get_adapter_name()
  return "codelldb"
end

---Returns the `codelldb` adapter configuration for `nvim-dap`.
---@return table
function M.get_adapter()
  if not config.codelldb_path or not config.lldb_lib_path or not config.port then
    notifications.send_error(
      "xcodebuild.nvim: codelldb is not properly configured, check your settings: integrations.codelldb"
    )
    return {}
  end

  return {
    type = "server",
    port = config.port,
    executable = {
      command = config.codelldb_path,
      args = {
        "--port",
        config.port,
        "--liblldb",
        config.lldb_lib_path,
      },
    },
  }
end

return M
