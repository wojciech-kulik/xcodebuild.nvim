---@mod xcodebuild.core.quickfix Quickfix List
---@brief [[
---This module is responsible for setting up the quickfix list with
---errors and warnings.
---@brief ]]

local util = require("xcodebuild.util")
local config = require("xcodebuild.core.config").options.quickfix
local testSearch = require("xcodebuild.tests.search")

local M = {}

---@private
---@class QuickfixError
---@field filename string
---@field lnum number
---@field col number
---@field text string
---@field type string

---Inserts build errors into the {list}.
---It skips duplicates.
---@param list QuickfixError[]
---@param errors ParsedBuildError[]
local function insert_build_errors(list, errors)
  local duplicates = {}

  for _, error in ipairs(errors) do
    if error.filepath then
      local line = error.lineNumber or 0
      local col = error.columnNumber or 0

      if not duplicates[error.filepath .. line .. col] then
        table.insert(list, {
          filename = error.filepath,
          lnum = line,
          col = col,
          text = error.message and error.message[1] or "",
          type = "E",
        })
        duplicates[error.filepath .. line .. col] = true
      end
    end
  end
end

---Inserts test failures into the {list}.
---@param list QuickfixError[]
---@param tests table<string,ParsedTest[]>
local function insert_failing_tests(list, tests)
  for _, testsPerClass in pairs(tests) do
    for _, test in ipairs(testsPerClass) do
      if not test.success and test.filepath and test.lineNumber then
        table.insert(list, {
          filename = test.filepath,
          lnum = test.lineNumber,
          text = test.message[1],
          type = "E",
        })
      end
    end
  end
end

---Inserts build warnings into the {list}.
---@param list QuickfixError[]
---@param warnings ParsedBuildWarning[]
local function insert_build_warnings(list, warnings)
  for _, warning in ipairs(warnings) do
    table.insert(list, {
      filename = warning.filepath,
      lnum = warning.lineNumber,
      col = warning.columnNumber or 0,
      text = warning.message[1],
      type = "W",
    })
  end
end

---Inserts test errors into the {list}.
---@param list QuickfixError[]
---@param testErrors ParsedTestError[]
local function insert_test_errors(list, testErrors)
  for _, error in ipairs(testErrors) do
    local target, filename = string.match(error.filepath, "(.-)/(.+)")

    if testSearch.targetsFilesMap and testSearch.targetsFilesMap[target] then
      for _, filepath in ipairs(testSearch.targetsFilesMap[target]) do
        if util.has_suffix(filepath, filename) then
          table.insert(list, {
            filename = filepath,
            lnum = error.lineNumber,
            text = error.message[1],
            type = "E",
          })
          break
        end
      end
    end
  end
end

---Sets the quickfix list with the given {report}.
---It sets build errors, build warnings, test failures and test errors
---if the corresponding options are enabled.
---@param report ParsedReport
---@see xcodebuild.xcode_logs.parser.ParsedReport
function M.set(report)
  if not config.show_warnings_on_quickfixlist and not config.show_errors_on_quickfixlist then
    return
  end

  local quickfix = {}

  if config.show_warnings_on_quickfixlist then
    insert_build_warnings(quickfix, report.buildWarnings or {})
  end

  if config.show_errors_on_quickfixlist then
    insert_build_errors(quickfix, report.buildErrors or {})
    insert_failing_tests(quickfix, report.tests or {})
    insert_test_errors(quickfix, report.testErrors or {})
  end

  table.sort(quickfix, function(a, b)
    if a.filename == b.filename then
      if a.lnum == b.lnum then
        return (a.col or 0) < (b.col or 0)
      end

      return a.lnum < b.lnum
    end

    return a.filename < b.filename
  end)

  vim.fn.setqflist(quickfix, "r")
end

return M
