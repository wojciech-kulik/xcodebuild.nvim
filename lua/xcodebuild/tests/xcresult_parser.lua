---@mod xcodebuild.tests.xcresult_parser Xcresult File Parser
---@brief [[
---This module is responsible for processing `xcresult` file
---and filling the report with the test data.
---
---Normally, processing logs from `xcodebuild` is enough to get
---the test data. However, when running tests using Swift Testing
---framework, some details like target name are missing.
---
---@brief ]]

local util = require("xcodebuild.util")
local testSearch = require("xcodebuild.tests.search")
local constants = require("xcodebuild.core.constants")

---@private
---@class XcTestNode
---@field name string
---@field nodeType string
---@field result string
---@field nodeIdentifier string|nil
---@field duration string|nil
---@field tags string[]|nil
---@field children XcTestNode[]|nil
---@field parent XcTestNode|nil

---@private
---@class XcresultOutput
---@field testNodes XcTestNode[]

local nodeType = {
  testPlan = "Test Plan",
  testBundle = "Unit test bundle",
  testCase = "Test Case",
  testSuite = "Test Suite",
  failureMessage = "Failure Message",
}

local M = {}

---@type table<string, string>
local ripgrepCache = {}

---Fills the parent property for all children
---for easier navigation.
---@param node XcTestNode
local function fill_parent(node)
  if node.children then
    for _, child in ipairs(node.children) do
      child.parent = node
      fill_parent(child)
    end
  end
end

---Finds the filepath using `ripgrep` for the given {suiteName}.
---@param suiteName string
---@return string|nil
local function find_filepath_using_ripgrep(suiteName)
  if ripgrepCache[suiteName] then
    return ripgrepCache[suiteName]
  end

  if vim.fn.executable("rg") == 0 then
    return nil
  end

  local paths = util.shell({
    "rg",
    "--max-count",
    "1",
    "--glob",
    "*.swift",
    "--files-with-matches",
    "--fixed-strings",
    '@Suite("' .. suiteName .. '"',
    vim.fn.getcwd(),
  })

  if not paths then
    return nil
  end

  for _, path in ipairs(paths) do
    if path and path ~= "" then
      ripgrepCache[suiteName] = path
      return path
    end
  end

  return nil
end

---Fixes the test id by adding the target id if it's missing.
---@param testId string|nil
---@param targetId string
---@return string|nil
local function fix_test_id(testId, targetId)
  if not testId then
    return nil
  end

  local fixedTestId = testId:gsub("%(%)", "")

  local _, count = fixedTestId:gsub("/", "")
  if count < 2 then
    return targetId .. "/" .. fixedTestId
  else
    return fixedTestId
  end
end

---Finds the filepath for the given {target} and {suiteId}.
---As a fallback, it uses the `suiteName` to find the filepath using `ripgrep`.
---@param target string
---@param suiteId string
---@param suiteName string
---@return string|nil
local function find_filepath(target, suiteId, suiteName)
  if target == constants.SwiftTestingTarget or suiteName == constants.SwiftTestingGlobal then
    return nil
  end

  return testSearch.find_filepath(target, suiteId) or find_filepath_using_ripgrep(suiteName)
end

---Returns the first match line number or nil.
---@param filepath string
---@param testName string|nil
---@return number|nil
local function find_test_line(filepath, testName)
  if not testName then
    return nil
  end

  local success, lines = util.readfile(filepath)
  if not success then
    return nil
  end

  for lineNumber, line in ipairs(lines) do
    if string.find(line, "func " .. testName .. "%(") then
      return lineNumber
    elseif string.find(line, '@Test("' .. testName .. '"', nil, true) then
      return lineNumber
    end
  end

  return nil
end

---Parses the error message and returns the message, filepath, and line number.
---@param message string|nil
---@return {message:string,filepath:string|nil,lineNumber:number|nil}|nil
local function extract_error(message)
  if not message then
    return nil
  end

  local filename, lineNumber, error = message:match("(.+):(%d+): (.*)")
  if not error then
    return { message = message }
  end

  return {
    message = error,
    filepath = filename and testSearch.find_filepath_by_filename(filename),
    lineNumber = lineNumber and tonumber(lineNumber),
  }
end

---Extracts the suite id from the test id.
---@param testId string|nil
---@return string|nil
local function extract_suite_id(testId)
  local parts = vim.split(testId or "", "/")

  if #parts == 3 then
    return parts[2]
  elseif #parts == 2 then
    return parts[1]
  else
    return nil
  end
end

---@param testNode XcTestNode
---@param targetId string|nil
---@return string, ParsedTest
local function parse_test(testNode, targetId)
  local suiteName = testNode.parent
      and testNode.parent.nodeType == nodeType.testSuite
      and testNode.parent.name
    or constants.SwiftTestingGlobal

  local suiteId = extract_suite_id(testNode.nodeIdentifier) or constants.SwiftTestingGlobal
  local targetIdUnwrapped = targetId or constants.SwiftTestingTarget
  local filepath = find_filepath(targetIdUnwrapped, suiteId, suiteName)
  local filename = filepath and util.get_filename(filepath)
  local testId = fix_test_id(testNode.nodeIdentifier, targetIdUnwrapped)
  local lineNumber = filepath and find_test_line(filepath, testNode.name)

  ---@type ParsedTest
  local test = {
    filepath = filepath,
    filename = filename,
    lineNumber = lineNumber,
    swiftTestingId = testId,
    target = targetIdUnwrapped,
    class = suiteName:gsub("/", " "),
    name = testNode.name and testNode.name:gsub("%([^%)]*%)", ""):gsub("/", " "),
    testResult = testNode.result == "Passed" and "passed" or "failed",
    success = testNode.result == "Passed",
    time = testNode.duration and testNode.duration:gsub("s", " seconds"):gsub(",", "."),
  }

  for _, child in ipairs(testNode.children or {}) do
    if child.nodeType == nodeType.failureMessage then
      local error = extract_error(child.name)
      if error then
        test.filepath = test.filepath or error.filepath
        test.filename = test.filepath and util.get_filename(test.filepath)

        if error.filepath == test.filepath then
          test.lineNumber = error.lineNumber or test.lineNumber or 1
        end

        if not test.message then
          test.message = {}
        end
        table.insert(test.message, error.message)
      end
    end
  end

  local key = targetIdUnwrapped .. ":" .. suiteName
  return key, test
end

---@param node XcTestNode
---@param targetName string|nil
---@return table<string, ParsedTest[]>
local function get_tests(node, targetName)
  local tests = {}

  if node.nodeType == nodeType.testCase then
    if node.result == "Skipped" then
      return tests
    end

    local key, test = parse_test(node, targetName)
    if not tests[key] then
      tests[key] = {}
    end

    table.insert(tests[key], test)
    return tests
  end

  if node.nodeType == nodeType.testSuite and node.name == "System Failures" then
    return tests
  end

  if node.nodeType == nodeType.testBundle then
    targetName = node.name
  end

  for _, child in ipairs(node.children or {}) do
    local childTests = get_tests(child, targetName)

    for key, value in pairs(childTests) do
      if not tests[key] then
        tests[key] = {}
      end

      for _, test in ipairs(value) do
        table.insert(tests[key], test)
      end
    end
  end

  return tests
end

---Fills the report with the data from the `xcresult` file.
---@param report ParsedReport
---@return boolean true if the report was updated, false otherwise.
function M.fill_xcresult_data(report)
  if not report.xcresultFilepath or not report.usesSwiftTesting then
    return false
  end

  local output = util.shell({
    "xcrun",
    "xcresulttool",
    "get",
    "test-results",
    "tests",
    "--path",
    report.xcresultFilepath,
  })

  if util.is_empty(output) then
    return false
  end

  ---@type XcresultOutput|nil
  local outputDecoded = vim.fn.json_decode(output)
  if not outputDecoded or util.is_empty(outputDecoded.testNodes) then
    return false
  end

  for _, node in ipairs(outputDecoded.testNodes) do
    fill_parent(node)
  end

  ripgrepCache = {}

  report.tests = get_tests(outputDecoded.testNodes[1])
  report.failedTestsCount = 0
  report.testsCount = 0

  for _, tests in pairs(report.tests) do
    for _, test in ipairs(tests) do
      report.failedTestsCount = report.failedTestsCount + (test.success and 0 or 1)
      report.testsCount = report.testsCount + 1
    end
  end

  return true
end

return M
