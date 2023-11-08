local util = require("xcodebuild.util")
local config = require("xcodebuild.config").options.marks

local M = {}

local function refresh_buf_diagnostics(bufnr, testClass, report)
  if not report.tests or not config.show_diagnostics then
    return
  end

  local ns = vim.api.nvim_create_namespace("xcodebuild-diagnostics")
  local diagnostics = {}
  local duplicates = {}

  for _, test in ipairs(report.tests[testClass] or {}) do
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

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  vim.diagnostic.set(ns, bufnr, diagnostics, {})
end

local function refresh_buf_marks(bufnr, testClass, tests)
  if not tests or not (config.show_test_duration or config.show_signs) then
    return
  end

  local ns = vim.api.nvim_create_namespace("xcodebuild-marks")
  local bufLines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local findTestLine = function(testName)
    for lineNumber, line in ipairs(bufLines) do
      if string.find(line, "func " .. testName .. "%(") then
        return lineNumber - 1
      end
    end

    return nil
  end

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

  for _, test in ipairs(tests[testClass] or {}) do
    local lineNumber = findTestLine(test.name)
    local testDuration = nil
    local signText = nil
    local signHighlight = nil

    if config.show_test_duration then
      if test.time then
        local text = "(" .. test.time .. ")"
        local highlight = test.success and config.success_test_duration_hl or config.failure_test_duration_hl
        testDuration = { text, highlight }
      else
        testDuration = { "" }
      end
    end

    if config.show_signs then
      signText = test.success and config.success_sign or config.failure_sign
      signHighlight = test.success and config.success_sign_hl or config.failure_sign_hl
    end

    if test.filepath and lineNumber then
      vim.api.nvim_buf_set_extmark(bufnr, ns, lineNumber, 0, {
        virt_text = { testDuration },
        sign_text = signText,
        sign_hl_group = signHighlight,
      })
    end
  end
end

function M.refresh_test_buffer(bufnr, file, report)
  local testClass = util.get_filename(file)
  refresh_buf_diagnostics(bufnr, testClass, report)
  refresh_buf_marks(bufnr, testClass, report.tests)
end

function M.refresh_all_test_buffers(report)
  if util.is_not_empty(report.buildErrors) then
    return
  end

  -- TODO: improve gsub - the conversion from wildcard to regex might not be reliable
  local filePattern = config.file_pattern
  local regexPattern = string.gsub(string.gsub(filePattern, "%.", "%%."), "%*", "%.%*")
  local testBuffers = util.get_bufs_by_matching_name(regexPattern)

  for _, buffer in ipairs(testBuffers or {}) do
    local testClass = util.get_filename(buffer.file)
    refresh_buf_diagnostics(buffer.bufnr, testClass, report)
    refresh_buf_marks(buffer.bufnr, testClass, report.tests)
  end
end

return M
