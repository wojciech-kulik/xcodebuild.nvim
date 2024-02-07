local util = require("xcodebuild.util")

local M = {}

M.report = {}
M.appdir = vim.fn.getcwd() .. "/.nvim/xcodebuild"
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

GETSNAPSHOTS_TOOL = "getsnapshots"
PROJECT_HELPER_TOOL = "project_helper.rb"

function M.tool_path(name)
  local pathComponents = vim.split(debug.getinfo(1).source:sub(2), "/", { plain = true })
  return table.concat(pathComponents, "/", 1, #pathComponents - 3) .. "/tools/" .. name
end

function M.create_app_dir()
  util.shell("mkdir -p .nvim/xcodebuild")
end

function M.read_original_logs()
  return vim.fn.readfile(M.original_logs_filepath)
end

function M.read_report()
  local success, json = pcall(vim.fn.readfile, M.report_filepath)
  return success and vim.fn.json_decode(json)
end

function M.write_report(report)
  local copy = report.output
  report.output = nil

  local json = vim.split(vim.fn.json_encode(report), "\n", { plain = true })
  vim.fn.writefile(json, M.report_filepath)

  report.output = copy
end

function M.write_original_logs(data)
  vim.fn.writefile(data, M.original_logs_filepath)
end

function M.read_build_logs()
  return vim.fn.readfile(M.build_logs_filepath)
end

function M.write_build_logs(data)
  vim.fn.writefile(data, M.build_logs_filepath)
end

function M.load_last_report()
  local parser = require("xcodebuild.parser")
  local quickfix = require("xcodebuild.quickfix")
  local diagnostics = require("xcodebuild.diagnostics")
  local config = require("xcodebuild.config").options
  local testSearch = require("xcodebuild.test_search")

  parser.clear()
  M.report = M.read_report() or {}

  if util.is_not_empty(M.report) then
    vim.defer_fn(function()
      testSearch.load_targets_map()
      quickfix.set(M.report)
      diagnostics.refresh_all_test_buffers(M.report)
    end, vim.startswith(config.test_search.file_matching, "lsp") and 1000 or 500)
  end
end

return M
