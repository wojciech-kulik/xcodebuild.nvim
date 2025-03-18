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
---@param productName string
---@param detached boolean|nil
---@param callback function|nil
---@return number # job id
function M.launch_app(appPath, productName, detached, callback)
  if detached == nil then
    detached = false
  end

  local executablePath = appPath .. "/Contents/MacOS/" .. productName
  local command = { executablePath }

  local runArgs = appdata.read_run_args()
  if runArgs then
    for _, value in ipairs(runArgs) do
      table.insert(command, value)
    end
  end

  local function write_logs(_, output)
    if output[#output] == "" then
      table.remove(output, #output)
    end
    appdata.append_app_logs(output)
  end

  appdata.clear_app_logs()

  if detached then
    util.call(callback)
  end

  return vim.fn.jobstart(command, {
    env = appdata.read_env_vars(),
    pty = not detached,
    detach = detached,
    on_stdout = write_logs,
    on_stderr = write_logs,
    on_exit = function(_, code)
      if not detached and code == 0 then
        util.call(callback)
      end

      if code ~= 0 then
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
    args = appdata.read_run_args(),
    stopOnEntry = false,
    waitFor = true,
    env = appdata.read_env_vars(),
  })

  util.call(callback)
end

return M
