---@mod xcodebuild.project.appdata App Data
---@brief [[
---This module provides functionality to manage the project
---data stored in `.nvim/xcodebuild` folder, such as logs,
---reports, snapshots, coverage, and settings.
---
---It also provides paths to the tools used by the plugin.
---
---All data is stored in the current working directory in
---the `.nvim/xcodebuild` folder. That's why it's important
---to always run the plugin from the root of the project.
---@brief ]]

---@class AppData
---@field report ParsedReport|table # The last test report (can be empty).
---@field appdir string # The path to the `.nvim/xcodebuild` folder.
---@field app_logs_filename string # The name of the app logs file.
---@field app_logs_filepath string # The path to the app logs file.
---@field original_logs_filename string # The name of the original logs file.
---@field original_logs_filepath string # The path to the original logs file.
---@field build_logs_filename string # The name of the build logs file.
---@field build_logs_filepath string # The path to the build logs file.
---@field report_filename string # The name of the report file.
---@field report_filepath string # The path to the report file.
---@field tests_filename string # The name of the tests file.
---@field tests_filepath string # The path to the tests file.
---@field snapshots_dir string # The path to the snapshots directory.
---@field coverage_filepath string # The path to the coverage file.
---@field coverage_report_filepath string # The path to the coverage report file.
---@field GETSNAPSHOTS_TOOL string # The name of the getsnapshots tool.
---@field PROJECT_HELPER_TOOL string # The name of the project helper tool.
---@field REMOTE_DEBUGGER_TOOL string # The name of the remote debugger tool.

local util = require("xcodebuild.util")

local M = {}

M.report = {}
M.appdir = vim.fn.getcwd() .. "/.nvim/xcodebuild"
M.app_logs_filename = "app_logs.log"
M.app_logs_filepath = M.appdir .. "/" .. M.app_logs_filename
M.original_logs_filename = "original_logs.log"
M.original_logs_filepath = M.appdir .. "/" .. M.original_logs_filename
M.build_logs_filename = "xcodebuild.log"
M.build_logs_filepath = M.appdir .. "/" .. M.build_logs_filename
M.report_filename = "report.json"
M.report_filepath = M.appdir .. "/" .. M.report_filename
M.tests_filename = "tests.json"
M.tests_filepath = M.appdir .. "/" .. M.tests_filename
M.snapshots_dir = M.appdir .. "/failing-snapshots"
M.coverage_filepath = M.appdir .. "/coverage.xccovarchive"
M.coverage_report_filepath = M.appdir .. "/coverage.json"

M.GETSNAPSHOTS_TOOL = "getsnapshots"
M.PROJECT_HELPER_TOOL = "project_helper.rb"
M.REMOTE_DEBUGGER_TOOL = "remote_debugger"

---Returns the path to the tool with the given {name}.
---@param name string
---@return string
function M.tool_path(name)
  local pathComponents = vim.split(debug.getinfo(1).source:sub(2), "/", { plain = true })
  return table.concat(pathComponents, "/", 1, #pathComponents - 4) .. "/tools/" .. name
end

---Creates the `.nvim/xcodebuild` folder if it doesn't exist.
function M.create_app_dir()
  util.shell("mkdir -p .nvim/xcodebuild")
end

---Reads the original Xcode logs.
---@return string[]
function M.read_original_logs()
  return vim.fn.readfile(M.original_logs_filepath)
end

---Writes the original Xcode logs to disk.
---@param data string[]
function M.write_original_logs(data)
  vim.fn.writefile(data, M.original_logs_filepath)
end

---Reads the last test report from disk.
---@return ParsedReport|nil
function M.read_report()
  local success, json = pcall(vim.fn.readfile, M.report_filepath)
  return success and vim.fn.json_decode(json) or nil
end

---Writes the given {report} to disk.
---@param report ParsedReport
function M.write_report(report)
  local copy = report.output
  report.output = nil

  local json = vim.split(vim.fn.json_encode(report), "\n", { plain = true })
  vim.fn.writefile(json, M.report_filepath)

  report.output = copy
end

---Reads the build logs from disk.
---These logs contain also the summary prepared by this
---plugin.
---@return string[]
function M.read_build_logs()
  return vim.fn.readfile(M.build_logs_filepath)
end

---Writes the build logs to disk.
---These logs contain also the summary prepared by this
---plugin.
---@param data string[]
function M.write_build_logs(data)
  vim.fn.writefile(data, M.build_logs_filepath)
end

---Loads the last test report from disk and updates the
---quickfix list and the diagnostics.
---Sets `M.report`.
function M.load_last_report()
  local logsParser = require("xcodebuild.xcode_logs.parser")
  local quickfix = require("xcodebuild.core.quickfix")
  local diagnostics = require("xcodebuild.tests.diagnostics")
  local config = require("xcodebuild.core.config").options
  local testSearch = require("xcodebuild.tests.search")

  logsParser.clear()
  M.report = M.read_report() or {}

  if util.is_not_empty(M.report) then
    vim.defer_fn(function()
      testSearch.load_targets_map()
      quickfix.set(M.report)
      diagnostics.refresh_all_test_buffers(M.report)
    end, vim.startswith(config.test_search.file_matching, "lsp") and 1000 or 500)
  end
end

---Clears the app logs and DAP console.
function M.clear_app_logs()
  local config = require("xcodebuild.core.config").options.console_logs

  if config.enabled then
    require("xcodebuild.integrations.dap").clear_console()
  end

  vim.fn.writefile({}, M.app_logs_filepath)
end

---Appends the given {output} to the app logs file and
---updates the DAP console.
---@param output string[]
function M.append_app_logs(output)
  local logFile = M.app_logs_filepath
  local config = require("xcodebuild.core.config").options.console_logs

  for index, line in ipairs(output) do
    output[index] = line:gsub("\r", "")
  end

  vim.fn.writefile(output, logFile, "a")

  if config.enabled then
    local log_lines = {}
    for _, line in ipairs(output) do
      if config.filter_line(line) then
        table.insert(log_lines, config.format_line(line))
      end
    end

    require("xcodebuild.integrations.dap").update_console(log_lines)
  end
end

return M
