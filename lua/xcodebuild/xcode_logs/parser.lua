local M = {}

local util = require("xcodebuild.util")
local testSearch = require("xcodebuild.tests.search")

-- state machine
local BEGIN = "BEGIN"
local TEST_START = "TEST_START"
local TEST_ERROR = "TEST_ERROR"
local BUILD_ERROR = "BUILD_ERROR"
local BUILD_WARNING = "BUILD_WARNING"

-- temp fields
local lineType = BEGIN
local lineData = {}
local lastTest = nil
local lastErrorTest = {}

-- report fields
local testsCount = 0
local tests = {}
local failedTestsCount = 0
local output = {}
local buildErrors = {}
local warnings = {}
local diagnostics = {}
local xcresultFilepath = nil

-- patterns
local swiftFilePattern = "[^%:]+%.swift"
local xcTestLogPattern = "%s+[%w_]+%[%d+%:%d+%]"

local function flush_test(message)
  if message then
    table.insert(lineData.message, message)
  end

  local key = testSearch.get_test_key(lineData.target, lineData.class)
  if key then
    tests[key] = tests[key] or {}
    table.insert(tests[key], lineData)
  end

  require("xcodebuild.tests.explorer").update_test_status(
    lineData.target .. "/" .. lineData.class .. "/" .. lineData.name,
    lineData.success and "passed" or "failed"
  )

  lastTest = lineData
  lineType = BEGIN
  lineData = {}
end

local function flush_error(line)
  if line then
    table.insert(lineData.message, line)
  end

  for _, item in ipairs(buildErrors) do
    if
      item.filepath == lineData.filepath
      and item.lineNumber == lineData.lineNumber
      and item.message[1] == lineData.message[1]
    then
      return
    end
  end

  table.insert(buildErrors, lineData)
  lineType = BEGIN
  lineData = {}
end

local function flush_warning(line)
  if line then
    table.insert(lineData.message, line)
  end

  for _, item in ipairs(warnings) do
    if
      item.filepath == lineData.filepath
      and item.lineNumber == lineData.lineNumber
      and item.message[1] == lineData.message[1]
    then
      return
    end
  end

  table.insert(warnings, lineData)
  lineType = BEGIN
  lineData = {}
end

local function flush_diagnostic(filepath, filename, lineNumber)
  for _, item in ipairs(diagnostics) do
    if
      item.filepath == filepath
      and item.lineNumber == lineNumber
      and item.message[1] == lineData.message[1]
    then
      return
    end
  end

  table.insert(diagnostics, {
    filepath = filepath,
    filename = filename,
    lineNumber = lineNumber,
    message = lineData.message,
  })
end

local function flush(line)
  if lineType == BUILD_ERROR then
    flush_error(line)
  elseif lineType == BUILD_WARNING then
    flush_warning(line)
  elseif lineType == TEST_ERROR then
    flush_test(line)
  end
end

local function sanitize(message)
  return string.match(message, "%-%[[%w_]+%.[%w_]+ %g+%] %: (.*)") or message
end

local function find_test_line(filepath, testName)
  local success, lines = pcall(vim.fn.readfile, filepath)
  if not success then
    return nil
  end

  for lineNumber, line in ipairs(lines) do
    if string.find(line, "func " .. testName .. "%(") then
      return lineNumber
    end
  end

  return nil
end

local function parse_build_error(line)
  if string.find(line, xcTestLogPattern) then
    return
  end

  if string.find(line, swiftFilePattern .. "%:%d+%:%d*%:? %w*%s*error%: .*") then
    local filepath, lineNumber, colNumber, message =
      string.match(line, "(" .. swiftFilePattern .. ")%:(%d+)%:(%d*)%:? %w*%s*error%: (.*)")
    if filepath and message then
      lineType = BUILD_ERROR
      lineData = {
        filename = util.get_filename(filepath),
        filepath = filepath,
        lineNumber = tonumber(lineNumber),
        columnNumber = tonumber(colNumber) or 0,
        message = { message },
      }
    end
  else
    local source, message = string.match(line, "(.*)%: %w*%s*error%: (.*)")
    message = message or string.match(line, "error%: (.*)")

    if message then
      lineType = BUILD_ERROR
      lineData = {
        source = source,
        message = { message },
      }
    end
  end
end

local function parse_test_error(line)
  if string.find(line, xcTestLogPattern) then
    return
  end

  local filepath, lineNumber, message =
    string.match(line, "(" .. swiftFilePattern .. ")%:(%d+)%:%d*%:? %w*%s*error%: (.*)")

  if filepath and message then
    -- count only the first error per test
    if lastErrorTest == nil then
      failedTestsCount = failedTestsCount + 1

      -- we flush test with error whenever we find an empty line
      -- however, a single test can fail multiple asserts
      -- therefore, we need to remember the last test to
      -- add the next failure to the report
      lastErrorTest = util.shallow_copy(lineData)
    end

    lineType = TEST_ERROR
    lineData.message = { sanitize(message) }
    lineData.testResult = "failed"
    lineData.success = false

    -- If file from error doesn't match test file, let's set lineNumber to test declaration line
    local filename = util.get_filename(filepath)
    if filename ~= lineData.filename then
      lineData.lineNumber = find_test_line(lineData.filepath, lineData.name)
      flush_diagnostic(filepath, filename, tonumber(lineNumber))
    else
      lineData.lineNumber = tonumber(lineNumber)
    end
  end
end

local function parse_warning(line)
  if string.find(line, xcTestLogPattern) then
    return
  end

  local filepath, lineNumber, columnNumber, message =
    string.match(line, "(" .. swiftFilePattern .. ")%:(%d+)%:(%d*)%:? %w*%s*warning%: (.*)")

  if filepath and message and util.has_prefix(filepath, vim.fn.getcwd()) then
    lineType = BUILD_WARNING
    lineData.filepath = filepath
    lineData.filename = util.get_filename(filepath)
    lineData.message = { message }
    lineData.lineNumber = tonumber(lineNumber) or 0
    lineData.columnNumber = tonumber(columnNumber) or 0
  end
end

local function parse_test_finished(line)
  lastErrorTest = nil

  if string.find(line, "^Test Case .*.%-") then
    local testResult, time = string.match(line, "^Test Case .*.%-%[[%w_]+%.[%w_]+ %g+%]. (%w+)% %((.*)%)%.")
    if lastTest then
      lastTest.time = time
      lastTest.testResult = testResult
      lastTest.success = testResult == "passed"
      lastTest = nil
      lineData = {}
      lineType = BEGIN
    else
      lineData.time = time
      lineData.testResult = testResult
      lineData.success = testResult == "passed"
      flush_test()
    end
  else -- when running with autogenerated plan
    local testClass, testName, testResult, time =
      string.match(line, "^Test case %'([%w_]+)%.(%g+)%(.*%' (%w+) .* %(([^%)]*)%)$")
    if testClass and testName and testResult then
      local filepath = testSearch.find_filepath("", testClass)

      lineData = {
        filepath = filepath,
        filename = filepath and util.get_filename(filepath) or nil,
        target = filepath and testSearch.find_target_for_file(filepath),
        class = testClass,
        name = testName,
        lineNumber = filepath and find_test_line(filepath, testName) or nil,
        testResult = testResult,
        success = testResult == "passed",
        time = time,
      }
      testsCount = testsCount + 1
      if not lineData.success then
        lineData.message = { "Failed" }
        failedTestsCount = failedTestsCount + 1
      end
      flush_test()
    end
  end
end

local function parse_test_started(line)
  local target, testClass, testName = string.match(line, "^Test Case .*.%-%[([%w_]+)%.([%w_]+) (%g+)%]")
  local filepath = testSearch.find_filepath(target, testClass)

  testsCount = testsCount + 1
  lastErrorTest = nil
  lastTest = nil
  lineType = TEST_START
  lineData = {
    filepath = filepath,
    filename = filepath and util.get_filename(filepath) or nil,
    target = target,
    class = testClass,
    name = testName,
  }
end

local function process_line(line)
  table.insert(output, line)

  -- POSSIBLE PATHS:
  -- BEGIN -> BUILD_ERROR -> BEGIN
  -- BEGIN -> BUILD_WARNING -> BEGIN
  -- BEGIN -> TEST_START -> passed -> BEGIN
  -- BEGIN -> TEST_START -> TEST_ERROR -> (failed) -> BEGIN

  if string.find(line, "^Test Case.*started%.") then
    -- build is finished - now it's time to load targets
    if testsCount == 0 then
      testSearch.load_targets_map()
    end

    parse_test_started(line)
  elseif string.find(line, "^Test [Cc]ase.*passed") or string.find(line, "^Test [Cc]ase.*failed") then
    parse_test_finished(line)
  elseif string.find(line, "error%:") then
    flush()

    -- found another failure within the same test
    -- restore previous data
    if testsCount > 0 and lineType == BEGIN and lastErrorTest then
      lineData = lastErrorTest
      lineType = TEST_START
      parse_test_error(line)
    elseif lineType == TEST_START then
      parse_test_error(line)
    elseif testsCount == 0 and lineType == BEGIN then
      parse_build_error(line)
    end
  elseif string.find(line, "warning%:") then
    flush()
    parse_warning(line)
  elseif string.find(line, "%s*~*%^~*%s*") then
    flush(line)
  elseif string.find(line, "^%s*$") then
    flush()
  elseif string.find(line, "^Linting") or string.find(line, "^note%:") then
    flush()
  elseif string.find(line, "%.xcresult$") then
    xcresultFilepath = string.match(line, "%s*(.*[^%.%/]+%.xcresult)")
  elseif lineType == TEST_ERROR or lineType == BUILD_ERROR or lineType == BUILD_WARNING then
    table.insert(lineData.message, line)
  end
end

function M.clear()
  lastTest = nil
  lastErrorTest = nil
  lineData = {}
  lineType = BEGIN

  tests = {}
  testsCount = 0
  failedTestsCount = 0
  output = {}
  buildErrors = {}
  warnings = {}
  diagnostics = {}
  xcresultFilepath = nil
end

function M.parse_logs(logLines)
  for _, line in ipairs(logLines) do
    process_line(line)
  end

  return {
    output = output,
    tests = tests,
    testsCount = testsCount,
    failedTestsCount = failedTestsCount,
    buildErrors = buildErrors,
    warnings = warnings,
    diagnostics = diagnostics,
    xcresultFilepath = xcresultFilepath,
  }
end

return M
