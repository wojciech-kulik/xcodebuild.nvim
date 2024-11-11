---@mod xcodebuild.tests.xcresult_parser Xcresult File Parser
---@brief [[
---This module is responsible for processing `xcresult` file
---and filling the report with the test data.
---
---When running tests using Swift Testing framework some information
---like target name are missing. This module fills the missing data.
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
---@class Xcresult
---@field testNodes XcTestNode[]

local nodeType = {
  testPlan = "Test Plan",
  testBundle = "Unit test bundle",
  testCase = "Test Case",
  testSuite = "Test Suite",
  failureMessage = "Failure Message",
}

local M = {}

---@param suite string
---@param node XcTestNode
---@return XcTestNode|nil
local function find_suite(suite, node)
  if node.nodeType == nodeType.testSuite and node.name == suite then
    return node
  end

  if node.children then
    for _, child in ipairs(node.children) do
      local resultNode = find_suite(suite, child)
      if resultNode then
        return resultNode
      end
    end
  end

  return nil
end

---@param node XcTestNode
local function fill_parent(node)
  if node.children then
    for _, child in ipairs(node.children) do
      child.parent = node
      fill_parent(child)
    end
  end
end

---@param testName string
---@param node XcTestNode
---@return XcTestNode|nil
local function find_test(testName, node)
  if node.children then
    for _, child in ipairs(node.children) do
      local childName = child.name and child.name:gsub("%(%)", "") or ""
      if child.nodeType == nodeType.testCase and childName == testName then
        return child
      end
    end
  end

  return nil
end

---@param testName string
---@param node XcTestNode
---@return XcTestNode|nil
local function find_global_test(testName, node)
  local nodeName = node.name and node.name:gsub("%(%)", "") or ""

  if
    node.nodeType == nodeType.testCase
    and nodeName == testName
    and node.parent.nodeType == nodeType.testBundle
  then
    return node
  end

  -- skip testSuite and testCase nodes because they can't contain global tests
  if node.nodeType == nodeType.testSuite or node.nodeType == nodeType.testCase then
    return nil
  end

  if node.children then
    for _, child in ipairs(node.children) do
      local result = find_global_test(testName, child)
      if result then
        return result
      end
    end
  end

  return nil
end

---@type table<string, string>
local ripgrepCache = {}

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

---Updates {reportTests} array.
---@param reportTests ParsedTest[]
---@param testsNode XcTestNode
---@param targetName string
local function fix_tests(reportTests, testsNode, targetName)
  for testIndex, test in ipairs(reportTests) do
    local xcTest = find_test(test.name, testsNode)

    -- fix target name
    reportTests[testIndex].target = targetName

    -- fix swiftTestingId
    if xcTest and xcTest.nodeIdentifier then
      local _, count = xcTest.nodeIdentifier:gsub("/", "")
      if count == 1 then
        reportTests[testIndex].swiftTestingId = targetName .. "/" .. xcTest.nodeIdentifier
      else
        reportTests[testIndex].swiftTestingId = xcTest.nodeIdentifier
      end
    else
      reportTests[testIndex].swiftTestingId = nil
    end

    -- fix filepath using ripgrep
    if not reportTests[testIndex].filepath and reportTests[testIndex].class then
      local filepath = testSearch.find_filepath(targetName, reportTests[testIndex].class)
        or find_filepath_using_ripgrep(reportTests[testIndex].class)

      reportTests[testIndex].filepath = filepath
      reportTests[testIndex].filename = filepath and util.get_filename(filepath)
    end
  end
end

---Updates {newReportTests} array.
---@param globalTests ParsedTest[]
---@param newReportTests table<string, ParsedTest[]>
---@param testsNode XcTestNode
local function fix_global_tests(globalTests, newReportTests, testsNode)
  for _, test in ipairs(globalTests or {}) do
    local testNode = find_global_test(test.name, testsNode)
    if not testNode then
      goto continue
    end

    local targetName = testNode.parent
        and testNode.parent.nodeType == nodeType.testBundle
        and testNode.parent.name
      or constants.SwiftTestingTarget

    -- fix swiftTestingId
    if testNode.nodeIdentifier then
      local _, count = testNode.nodeIdentifier:gsub("/", "")
      if count == 1 then
        test.swiftTestingId = targetName .. "/" .. testNode.nodeIdentifier
      else
        test.swiftTestingId = testNode.nodeIdentifier
      end
    else
      test.swiftTestingId = nil
    end

    -- fix target
    test.target = targetName

    -- insert
    local key = targetName .. ":" .. constants.SwiftTestingGlobal
    if not newReportTests[key] then
      newReportTests[key] = {}
    end
    table.insert(newReportTests[key], test)

    ::continue::
  end
end

---Fills the report with the data from the `xcresult` file.
---
---Fixes target name and filepath.
---It also adds the {swiftTestingId} to the test.
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

  ---@type Xcresult|nil
  local xcresult = vim.fn.json_decode(output)
  if not xcresult or util.is_empty(xcresult.testNodes) then
    return false
  end

  for _, node in ipairs(xcresult.testNodes) do
    fill_parent(node)
  end

  ---@type table<string, ParsedTest[]>
  local newReportTests = {}
  ripgrepCache = {}

  fix_global_tests(
    report.tests[constants.SwiftTestingTarget .. ":" .. constants.SwiftTestingGlobal],
    newReportTests,
    xcresult.testNodes[1]
  )

  for key, reportTests in pairs(report.tests) do
    local target, suite = string.match(key, "([^:]+):([^:]+)")
    if target ~= constants.SwiftTestingTarget then
      newReportTests[key] = reportTests
      goto continue
    end

    if suite == constants.SwiftTestingGlobal then
      goto continue
    end

    local suiteNode = find_suite(suite, xcresult.testNodes[1])
    if not suiteNode then
      newReportTests[key] = reportTests
      goto continue
    end

    local targetName = suiteNode.parent
        and suiteNode.parent.nodeType == nodeType.testBundle
        and suiteNode.parent.name
      or constants.SwiftTestingTarget

    newReportTests[targetName .. ":" .. suiteNode.name] = reportTests

    if targetName and targetName ~= constants.SwiftTestingTarget then
      fix_tests(reportTests, suiteNode, targetName)
    end

    ::continue::
  end

  report.tests = newReportTests

  return true
end

return M
