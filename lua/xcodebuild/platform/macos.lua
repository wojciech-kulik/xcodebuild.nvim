---@mod xcodebuild.platform.macos macOS Platform Integration
---@brief [[
---This module is responsible for the integration of macOS platform with `nvim-dap`.
---@brief ]]

local util = require("xcodebuild.util")
local appdata = require("xcodebuild.project.appdata")

local M = {}

---Simply starts the application on macOS.
---@param appPath string
---@param productName string
---@param callback function|nil
---@return number # job id
function M.launch_app(appPath, productName, callback)
  local path = appPath .. "/Contents/MacOS/" .. productName
  util.call(callback)
  return vim.fn.jobstart(path, { detach = true })
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
  })

  util.call(callback)
end

return M
