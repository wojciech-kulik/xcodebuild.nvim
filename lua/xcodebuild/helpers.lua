---@mod xcodebuild.helpers Helpers
---@brief [[
---This module contains general helper functions used across the plugin.
---
---|xcodebuild.util| is for general language utils and |xcodebuild.helpers|
---are for plugin specific utils.
---@brief ]]

---@private
---@class Cancellable
---@field currentJobId number|nil

local M = {}

---Cancels the current action from {source} module.
---@param source Cancellable
local function cancel(source)
  if source.currentJobId then
    if vim.fn.jobstop(source.currentJobId) == 1 then
      require("xcodebuild.broadcasting.events").action_cancelled()
    end

    source.currentJobId = nil
  end
end

---Sends a notification with a small delay to fix some glitches.
---@param text string
function M.defer_send(text)
  vim.defer_fn(function()
    require("xcodebuild.broadcasting.notifications").send(text)
  end, 100)
end

---Cancels all running actions from all modules.
function M.cancel_actions()
  local success, dap = pcall(require, "dap")
  if success and dap.session() then
    dap.terminate()
  end

  cancel(require("xcodebuild.platform.device"))
  cancel(require("xcodebuild.project.builder"))
  cancel(require("xcodebuild.tests.runner"))
  require("xcodebuild.core.previews").cancel()
  require("xcodebuild.platform.device").kill_app()
end

---Validates if the project is configured.
---It sends an error notification if the project is not configured.
---@param opts {requiresXcodeproj:boolean|nil, requiresApp:boolean|nil, silent: boolean|nil}|nil
---@return boolean
function M.validate_project(opts)
  opts = opts or {}
  local projectConfig = require("xcodebuild.project.config")
  local notifications = require("xcodebuild.broadcasting.notifications")
  local requiresApp = opts.requiresApp
  local requiresXcodeproj = opts.requiresXcodeproj or requiresApp

  local send_error = function(message)
    if not opts.silent then
      notifications.send_error(message)
    end
  end

  if requiresXcodeproj and projectConfig.is_spm_configured() then
    send_error("This operation is not supported for Swift Package.")
    return false
  end

  if requiresApp and projectConfig.is_library_configured() then
    send_error("This operation is not supported for Xcode Library.")
    return false
  end

  if requiresApp and not projectConfig.is_app_configured() then
    send_error("The project is missing some details. Please run XcodebuildSetup first.")
    return false
  end

  if
    requiresXcodeproj
    and not projectConfig.is_app_configured()
    and not projectConfig.is_library_configured()
  then
    send_error("The project is missing some details. Please run XcodebuildSetup first.")
    return false
  end

  if not projectConfig.is_configured() then
    send_error("The project is missing some details. Please run XcodebuildSetup first.")
    return false
  end

  return true
end

---Clears the state before the next build/test action.
function M.clear_state()
  local snapshots = require("xcodebuild.tests.snapshots")
  local testSearch = require("xcodebuild.tests.search")
  local logsParser = require("xcodebuild.xcode_logs.parser")
  local config = require("xcodebuild.core.config").options

  if config.auto_save then
    vim.cmd("silent wa!")
  end

  snapshots.delete_snapshots()
  logsParser.clear()
  testSearch.clear()
end

---Finds all swift files in project working directory.
---Returns a map of filename to list of filepaths.
---@return table<string, string[]>
function M.find_all_swift_files()
  local util = require("xcodebuild.util")

  local allFiles
  if util.is_fd_installed() then
    -- stylua: ignore
    allFiles = util.shell({
      "fd",
      "-I",
      ".*\\.swift$",
      vim.fn.getcwd(),
      "--type", "f",
    })
  else
    -- stylua: ignore
    allFiles = util.shell({
      "find",
      vim.fn.getcwd(),
      "-type", "d",
      "-path", "*/.*",
      "-prune",
      "-o",
      "-type", "f",
      "-iname", "*.swift",
      "-print",
    })
  end

  local map = {}

  for _, filepath in ipairs(allFiles) do
    local filename = util.get_filename(filepath)
    if filename then
      map[filename] = map[filename] or {}
      table.insert(map[filename], filepath)
    end
  end

  return map
end

---Returns the major version of the OS (ex. 17 for 17.1.1).
---It uses the device from the project configuration.
---@return number|nil
function M.get_major_os_version()
  local settings = require("xcodebuild.project.config").settings
  return settings.os and tonumber(vim.split(settings.os, ".", { plain = true })[1]) or nil
end

---Returns the minor version of the OS (ex. 1 for 17.1.2).
---It uses the device from the project configuration.
---@return number|nil
function M.get_minor_os_version()
  local settings = require("xcodebuild.project.config").settings
  return settings.os and tonumber(vim.split(settings.os, ".", { plain = true })[2]) or nil
end

---Wraps any nvim_buf_set_option() call to ensure forward compatibility.
---The function is required because nvim_buf_set_option() was deprecated in nvim-0.10.
---@param bufnr number
---@param name string
---@param value any
function M.buf_set_option(bufnr, name, value)
  if vim.fn.has("nvim-0.10") == 1 then
    vim.api.nvim_set_option_value(name, value, { buf = bufnr })
  else
    vim.api.nvim_buf_set_option(bufnr, name, value)
  end
end

---Wraps any nvim_win_set_option() call to ensure forward compatibility.
---The function is required because nvim_win_set_option() was deprecated in nvim-0.10.
---@param winnr number
---@param name string
---@param value any
function M.win_set_option(winnr, name, value)
  if vim.fn.has("nvim-0.10") == 1 then
    vim.api.nvim_set_option_value(name, value, { win = winnr })
  else
    vim.api.nvim_win_set_option(winnr, name, value)
  end
end

---Enables `modifiable` and updates the buffer using {updateFoo}.
---After the operation, it restores the `modifiable` to `false`.
---@param bufnr number|nil
---@param updateFoo function
function M.update_readonly_buffer(bufnr, updateFoo)
  if not bufnr or not vim.api.nvim_buf_is_loaded(bufnr) then
    return
  end

  M.buf_set_option(bufnr, "readonly", false)
  M.buf_set_option(bufnr, "modifiable", true)
  updateFoo()
  M.buf_set_option(bufnr, "modifiable", false)
  M.buf_set_option(bufnr, "modified", false)
  M.buf_set_option(bufnr, "readonly", true)
end

return M
