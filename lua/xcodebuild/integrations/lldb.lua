---@mod xcodebuild.integrations.lldb DAP Configurations - lldb
---@tag xcodebuild.lldb
---@brief [[
---This module contains DAP configurations for `lldb-dap` provided by `xcrun lldb-dap`.
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

local util = require("xcodebuild.util")
local appdata = require("xcodebuild.project.appdata")
local constants = require("xcodebuild.core.constants")
local config = require("xcodebuild.core.config").options.integrations.lldb
local notifications = require("xcodebuild.broadcasting.notifications")
local projectConfig = require("xcodebuild.project.config")

---Returns path to the built application.
---@return string
local function get_program_path()
  return projectConfig.settings.appPath
end

---Waits for the application to start and returns its PID.
---@return thread|nil # coroutine with pid
local function wait_for_pid()
  local co = coroutine
  local productName = projectConfig.settings.productName
  local xcode = require("xcodebuild.core.xcode")

  if not productName then
    notifications.send_error("You must build the application first")
    return
  end

  return co.create(function(dap_run_co)
    local pid = nil
    local isDevice = constants.is_device(projectConfig.settings.platform)

    notifications.send("Attaching debugger...")
    for _ = 1, 10 do
      util.shell("sleep 1")

      if isDevice then
        pid = require("xcodebuild.platform.device_proxy").find_app_pid(productName)
      else
        pid = xcode.get_app_pid(productName, projectConfig.settings.platform)
      end

      if tonumber(pid) then
        break
      end
    end

    if not tonumber(pid) then
      notifications.send_error("Launching the application timed out")

      ---@diagnostic disable-next-line: deprecated
      co.close(dap_run_co)
    end

    co.resume(dap_run_co, pid)
  end)
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
    pid = wait_for_pid,
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
    request = request,
    cwd = vim.fn.getcwd(),
    stopOnEntry = false,
    waitFor = true,
    program = get_program_path,
  }

  dapConfig.initCommands = { "platform select remote-ios" }
  dapConfig.preRunCommands = {
    function()
      return "target create '" .. projectConfig.settings.appPath .. "'"
    end,

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
  }

  if request == "attach" then
    dapConfig.attachCommands = {
      function()
        local pid = deviceProxy.find_app_pid(projectConfig.settings.productName)
        if not pid or pid == "" then
          notifications.send_error("Failed to find the app PID on the device.")
          return "platform status"
        end
        appdata.append_app_logs({ "App PID: " .. pid })

        return "process attach --pid " .. pid
      end,
    }
  else
    local env = appdata.read_env_vars()
    local args = appdata.read_run_args()
    local envString = ""
    local argsString = ""

    if env then
      for k, v in pairs(env) do
        envString = string.format("%s -E '%s=%s'", envString, k, v)
      end
    end

    if args then
      for _, v in ipairs(args) do
        argsString = argsString .. " " .. v
      end
    end

    dapConfig.launchCommands = {
      "process launch --stop-at-entry" .. envString .. argsString,
    }
  end

  return dapConfig
end

---Returns the name of the adapter.
---@return string
function M.get_adapter_name()
  return "lldb-dap"
end

---Returns the `lldb` adapter configuration for `nvim-dap`.
---@return table
function M.get_adapter()
  return {
    type = "server",
    port = config.port,
    executable = {
      command = "xcrun",
      args = {
        "lldb-dap",
        "--port",
        config.port,
      },
    },
  }
end

return M
