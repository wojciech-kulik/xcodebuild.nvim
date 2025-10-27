---@mod xcodebuild.platform.macos macOS Platform Integration
---@brief [[
---This module is responsible for the integration of macOS platform with `nvim-dap`.
---@brief ]]

local util = require("xcodebuild.util")
local appdata = require("xcodebuild.project.appdata")
local notifications = require("xcodebuild.broadcasting.notifications")

local PLUGIN_ID = "xcodebuild-macos-debugger"

local M = {}

---Simply starts the application on macOS.
---@param appPath string
---@param callback function|nil
---@return number # job id
function M.launch_app(appPath, callback)
  local command = { "open", appPath }
  local fifoPath = "/tmp/xcodebuild_nvim_" .. util.get_filename(appPath) .. ".fifo"

  local isStdbufInstalled = vim.fn.executable("stdbuf") ~= 0
  if isStdbufInstalled then
    vim.fn.delete(fifoPath)
    vim.fn.system({ "mkfifo", fifoPath })

    command = {
      "stdbuf",
      "-o0",
      "open",
      "--stdout",
      fifoPath,
      appPath,
    }

    appdata.clear_app_logs()
  end

  local runArgs = appdata.read_run_args()
  if runArgs then
    table.insert(command, "--args")
    for _, value in ipairs(runArgs) do
      table.insert(command, value)
    end
  end

  local launchJobId = vim.fn.jobstart(command, {
    clear_env = true,
    env = appdata.read_env_vars(),
    on_exit = function(_, code)
      if code == 0 then
        util.call(callback)
      else
        notifications.send_warning("Could not launch app, code: " .. code)
      end
    end,
  })

  if not isStdbufInstalled then
    return launchJobId
  end

  local function write_logs(_, output)
    if output[#output] == "" then
      table.remove(output, #output)
    end
    appdata.append_app_logs(output)
  end

  return vim.fn.jobstart({ "cat", fifoPath }, {
    on_stdout = write_logs,
    on_stderr = write_logs,
    on_exit = function()
      vim.fn.delete(fifoPath)
      write_logs(nil, { "", "[Process finished]" })
    end,
  })
end

---Starts the application on macOS and starts the debugger.
---@param callback function|nil
---@return number|nil # job id
function M.launch_and_debug(callback)
  local success, dap = pcall(require, "dap")
  local debugger = require("xcodebuild.platform.debugger")

  if not success then
    error("xcodebuild.nvim: Could not load nvim-dap plugin")
    return nil
  end

  appdata.clear_app_logs()

  dap.listeners.after.event_output[PLUGIN_ID] = function(_, body)
    if not body or not body.output then
      return
    end

    local message, _ = body.output:gsub("\r", "")
    local lines = vim.split(message, "\n", { plain = true, trimempty = true })
    appdata.append_app_logs(lines)
  end

  dap.listeners.after.event_exited[PLUGIN_ID] = function()
    dap.listeners.after.event_output[PLUGIN_ID] = nil
    dap.listeners.after.event_disconnect[PLUGIN_ID] = nil
  end

  dap.run(debugger.get_macos_configuration())
  util.call(callback)
end

return M
