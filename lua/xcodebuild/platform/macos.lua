---@mod xcodebuild.platform.macos macOS Platform Integration
---@brief [[
---This module is responsible for the integration of macOS platform with `nvim-dap`.
---@brief ]]

local util = require("xcodebuild.util")
local appdata = require("xcodebuild.project.appdata")
local notifications = require("xcodebuild.broadcasting.notifications")

local M = {}

---Simply starts the application on macOS.
---@param appPath string
---@param callback function|nil
---@return number # job id
function M.launch_app(appPath, callback)
  return vim.fn.jobstart({ "open", appPath }, {
    env = appdata.read_env_vars(),
    on_exit = function(_, code)
      if code == 0 then
        util.call(callback)
      else
        notifications.send_warning("Could not launch app, code: " .. code)
      end
    end,
  })
end

---Starts the application on macOS and starts the debugger.
---@param appPath string
---@param callback function|nil
---@return number|nil # job id
function M.launch_and_debug(appPath, callback)
  local success, dap = pcall(require, "dap")

  if not success then
    error("xcodebuild.nvim: Could not load nvim-dap plugin")
    return nil
  end

  appdata.clear_app_logs()

  dap.run({
    name = "macOS Debugger",
    type = "codelldb",
    request = "launch",
    cwd = "${workspaceFolder}",
    program = appPath,
    stopOnEntry = false,
    waitFor = true,
    env = appdata.read_env_vars(),
  })

  util.call(callback)
end

return M
