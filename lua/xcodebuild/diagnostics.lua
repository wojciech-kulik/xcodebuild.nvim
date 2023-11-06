local M = {}

local util = require("xcodebuild.util")
local config = require("xcodebuild.config").options.marks

function M.refresh_diagnostics(bufnr, testClass, report)
  if not report.tests or not config.show_diagnostics then
    return
  end

  local ns = vim.api.nvim_create_namespace("xcodebuild-diagnostics")
  local diagnostics = {}
  local duplicates = {}

  for _, test in ipairs(report.tests[testClass] or {}) do
    if not test.success and test.filepath and test.lineNumber and not duplicates[test.filepath .. test.lineNumber] then
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

function M.set_buf_marks(bufnr, testClass, tests)
  if not tests then
    return
  end

  local ns = vim.api.nvim_create_namespace("xcodebuild-marks")
  local successSign = config.success_sign
  local failureSign = config.failure_sign
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
    if config.show_test_duration then
      testDuration = test.time
          and {
            "(" .. test.time .. ")",
            test.success and config.success_test_duration_hl or config.failure_test_duration_hl,
          }
        or { "" }
    end

    local signText = nil
    if config.show_signs then
      signText = test.success and successSign or failureSign
    end

    if test.filepath and lineNumber and (config.show_test_duration or config.show_signs) then
      vim.api.nvim_buf_set_extmark(bufnr, ns, lineNumber, 0, {
        virt_text = { testDuration },
        sign_text = signText,
        sign_hl_group = test.success and config.success_sign_hl or config.failure_sign_hl,
      })
    end
  end
end

function M.refresh_buf_diagnostics(report)
  if report.buildErrors and report.buildErrors[1] then
    return
  end

  local buffers = util.get_bufs_by_name_matching(".*/.*[Tt]est[s]?%.swift$")

  for _, buffer in ipairs(buffers or {}) do
    local testClass = util.get_filename(buffer.file)
    M.refresh_diagnostics(buffer.bufnr, testClass, report)
    M.set_buf_marks(buffer.bufnr, testClass, report.tests)
  end
end

return M
