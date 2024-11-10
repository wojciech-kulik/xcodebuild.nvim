---@mod xcodebuild.tests.diagnostics Test Diagnostics
---@brief [[
---This module is responsible for handling diagnostics and marks for test files.
---@brief ]]

local util = require("xcodebuild.util")
local config = require("xcodebuild.core.config").options.marks
local testSearch = require("xcodebuild.tests.search")
local quick = require("xcodebuild.integrations.quick")

local M = {}

local diagnosticsNamespace = vim.api.nvim_create_namespace("xcodebuild-diagnostics")
local marksNamespace = vim.api.nvim_create_namespace("xcodebuild-marks")

---@type string|nil
local requestedRefreshForFile

---Returns the test class key for the given buffer.
---@param bufnr number
---@param report ParsedReport
---@return string|nil
---@see xcodebuild.tests.search.get_test_key_for_file
local function find_test_class(bufnr, report)
  local filepath = vim.api.nvim_buf_get_name(bufnr)

  -- check if a test class with matching filename exists
  local filename = util.get_filename(filepath)
  local testClassKey = testSearch.get_test_key_for_file(filepath, filename)
  if testClassKey and (not report.tests or report.tests[testClassKey]) then
    return testClassKey
  end

  -- if not try finding the name in the source code
  local lines = vim.api.nvim_buf_get_lines(bufnr, 1, -1, false)
  for index, line in ipairs(lines) do
    local class = string.match(line, "class ([^:%s]+)%s*%:?")
    local previousLine = (index > 1 and lines[index - 1]) or ""
    if not string.find(line, "@Suite") and not string.find(previousLine, "@Suite") and class then
      return testSearch.get_test_key_for_file(filepath, class)
    end
  end

  -- if not then maybe it's SwiftTesting, so just find a test with that filepath
  for key, tests in pairs(report.tests) do
    for _, test in ipairs(tests) do
      if test.filepath == filepath then
        return key
      end
    end
  end

  return nil
end

---Refreshes the diagnostics for the given buffer.
---@param bufnr number
---@param testClass string
---@param report ParsedReport
---@param quickTests table<string,QuickTest>|nil
local function refresh_buf_diagnostics(bufnr, testClass, report, quickTests)
  if not report.tests or not config.show_diagnostics then
    return
  end

  local diagnostics = {}
  local duplicates = {}

  for _, test in ipairs(report.tests[testClass] or {}) do
    test.lineNumber = test.lineNumber or (quickTests and quickTests[test.name] and quickTests[test.name].row)

    if
      not test.success
      and test.filepath
      and test.lineNumber
      and not duplicates[test.filepath .. test.lineNumber]
    then
      table.insert(diagnostics, {
        bufnr = bufnr,
        lnum = test.lineNumber - 1,
        col = 0,
        severity = vim.diagnostic.severity.ERROR,
        source = "xcodebuild",
        message = table.concat(test.message, "\n"),
        user_data = {},
      })
      duplicates[test.filepath .. test.lineNumber] = true
    end
  end

  vim.diagnostic.reset(diagnosticsNamespace, bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, diagnosticsNamespace, 0, -1)
  vim.diagnostic.set(diagnosticsNamespace, bufnr, diagnostics, {})
end

---Refreshes the marks for the given buffer.
---@param bufnr number
---@param testClass string
---@param tests ParsedTest[]
---@param quickTests table<string,QuickTest>|nil
local function refresh_buf_marks(bufnr, testClass, tests, quickTests)
  if not tests or not (config.show_test_duration or config.show_signs) then
    return
  end

  local bufLines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local findTestLine = function(testName)
    for lineNumber, line in ipairs(bufLines) do
      if string.find(line, "func " .. testName .. "%(") then
        return lineNumber - 1
      end
    end

    return nil
  end

  vim.api.nvim_buf_clear_namespace(bufnr, marksNamespace, 0, -1)

  for _, test in ipairs(tests[testClass] or {}) do
    local lineNumber = findTestLine(test.name)
      or (quickTests and quickTests[test.name] and quickTests[test.name].row - 1)
    local testDuration = nil
    local signText = nil
    local signHighlight = nil

    if config.show_test_duration then
      if test.time then
        local text = "(" .. test.time .. ")"
        local highlight = test.success and "XcodebuildTestSuccessDurationSign"
          or "XcodebuildTestFailureDurationSign"
        testDuration = { text, highlight }
      else
        testDuration = { "" }
      end
    end

    if config.show_signs then
      signText = test.success and config.success_sign or config.failure_sign
      signHighlight = test.success and "XcodebuildTestSuccessSign" or "XcodebuildTestFailureSign"
    end

    if test.filepath and lineNumber then
      vim.api.nvim_buf_set_extmark(bufnr, marksNamespace, lineNumber, 0, {
        virt_text = { testDuration },
        sign_text = signText,
        sign_hl_group = signHighlight,
      })
    end
  end
end

---Refreshes the diagnostics and marks for the given buffer.
---@param bufnr number
---@param report ParsedReport
---@see xcodebuild.xcode_logs.parser.ParsedReport
function M.refresh_test_buffer(bufnr, report)
  local testClass = find_test_class(bufnr, report)
  if testClass then
    local quickTests
    if quick.is_enabled() and quick.contains_quick_tests(bufnr) then
      quickTests = quick.find_quick_tests(bufnr)
    end

    refresh_buf_diagnostics(bufnr, testClass, report, quickTests)
    refresh_buf_marks(bufnr, testClass, report.tests, quickTests)
  end
end

---Refreshes diagnostics and marks for the test buffer with the given name.
---
---It implements a debounce mechanism to avoid refreshing
---the same buffer multiple times.The window is 1 second.
---
---Note: this function will affect the buffer after 1 second.
---To refresh the buffer instantly use `refresh_test_buffer`.
---
---@param name string
---@param report ParsedReport
function M.refresh_test_buffer_by_name(name, report)
  if requestedRefreshForFile == name then
    return
  end

  requestedRefreshForFile = name

  vim.defer_fn(function()
    requestedRefreshForFile = nil

    local bufnr = util.get_buf_by_name(name)
    if bufnr and vim.api.nvim_buf_is_loaded(bufnr) then
      M.refresh_test_buffer(bufnr, report)
    end
  end, 1000)
end

---Refreshes diagnostics and marks for all test buffers.
---@param report ParsedReport
---@see xcodebuild.xcode_logs.parser.ParsedReport
function M.refresh_all_test_buffers(report)
  if util.is_not_empty(report.buildErrors) then
    return
  end

  M.clear_marks()

  local filePathToBufnr = {}
  for _, bufnr in ipairs(util.get_buffers()) do
    local filepath = vim.api.nvim_buf_get_name(bufnr)
    filePathToBufnr[filepath] = bufnr
  end

  for _, testsPerClass in pairs(report.tests) do
    for _, test in ipairs(testsPerClass) do
      if test.filepath and filePathToBufnr[test.filepath] then
        M.refresh_test_buffer(filePathToBufnr[test.filepath], report)
        break -- all tests within the class are in the same file
      end
    end
  end
end

---Clears marks and diagnostics.
function M.clear()
  for _, bufnr in ipairs(util.get_buffers()) do
    vim.diagnostic.reset(diagnosticsNamespace, bufnr)
    vim.api.nvim_buf_clear_namespace(bufnr, marksNamespace, 0, -1)
    vim.api.nvim_buf_clear_namespace(bufnr, diagnosticsNamespace, 0, -1)
  end
end

---Clears marks.
function M.clear_marks()
  for _, bufnr in ipairs(util.get_buffers()) do
    vim.api.nvim_buf_clear_namespace(bufnr, marksNamespace, 0, -1)
  end
end

---Set up highlights for tests.
function M.setup()
  -- stylua: ignore start
  vim.api.nvim_set_hl(0, "XcodebuildTestSuccessSign", { link = "DiagnosticSignOk", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildTestFailureSign", { link = "DiagnosticSignError", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildTestSuccessDurationSign", { link = "DiagnosticSignWarn", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildTestFailureDurationSign", { link = "DiagnosticSignError", default = true })
  -- stylua: ignore end
end

return M
