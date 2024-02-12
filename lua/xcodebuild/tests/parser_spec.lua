local assert = require("luassert")
local parser = require("xcodebuild.parser")
local util = require("xcodebuild.util")
local cwd = vim.fn.getcwd()
local recordSnapshots = false

local mockSwiftFiles = function()
  local filetree = vim.fn.readfile(cwd .. "/lua/xcodebuild/tests/test_data/file_tree.txt")

  ---@diagnostic disable-next-line: duplicate-set-field
  require("xcodebuild.util").shell = function()
    return filetree
  end

  vim.fn.getcwd = function()
    return "/Users/john/repositories/calendar-app-ios"
  end

  ---@diagnostic disable-next-line: duplicate-set-field
  require("xcodebuild.xcode").get_targets_filemap = function(_)
    return {
      ["ShortcutRecorderCrashTests"] = {
        "/Users/john/repo/something/ShortcutRecorder.swift",
      },
      ["ViewModelTests"] = {
        "/Users/john/repo/something/Tests/ViewModel.swift",
      },
      ["Some_TestUITestsLaunchTests"] = {
        "/Users/john/repo/something/Tests/SomeFile1.swift",
      },
      ["Some_TestUITests"] = {
        "/Users/john/repo/something/Tests/SomeFile2.swift",
      },
      ["Some_TestTests"] = {
        "/Users/john/repo/something/Tests/SomeFile3.swift",
      },
    }
  end
end

local mockLSP = function()
  local filetree = vim.fn.readfile(cwd .. "/lua/xcodebuild/tests/test_data/file_tree.txt")

  local filetreeMap = {}
  for _, file in ipairs(filetree) do
    local className = util.get_filename(file)
    if className ~= nil then
      filetreeMap[className] = file
    end
  end

  filetreeMap["ShortcutRecorderCrashTests"] = "/Users/john/repo/something/ShortcutRecorder.swift"
  filetreeMap["ViewModelTests"] = "/Users/john/repo/something/Tests/ViewModel.swift"
  filetreeMap["Some_TestUITestsLaunchTests"] = "/Users/john/repo/something/Tests/SomeFile1.swift"
  filetreeMap["Some_TestUITests"] = "/Users/john/repo/something/Tests/SomeFile2.swift"
  filetreeMap["Some_TestTests"] = "/Users/john/repo/something/Tests/SomeFile3.swift"

  vim.lsp.get_active_clients = function(_)
    return { { id = 1 } }
  end
  vim.lsp.get_buffers_by_client_id = function(_)
    return { 0 }
  end
  vim.lsp.buf_request_all = function(_, _, params, callback)
    if not filetreeMap[params.query] then
      callback(nil)
      return
    end

    callback({
      {
        result = {
          {
            name = params.query,
            kind = 5,
            location = {
              uri = filetreeMap[params.query],
            },
          },
        },
      },
    })
  end
end

local runTestCase = function(caseId)
  require("xcodebuild.config").options.test_search.target_matching = false

  local expectedResultPath = cwd .. "/lua/xcodebuild/tests/test_data/tc" .. caseId .. "_out.log"
  local exists, expectedResult = pcall(vim.fn.readfile, expectedResultPath)
  local log = vim.fn.readfile(cwd .. "/lua/xcodebuild/tests/test_data/tc" .. caseId .. ".log")
  mockSwiftFiles()
  mockLSP()
  parser.clear()

  local report = parser.parse_logs(log)
  report.output = {}
  local result = vim.split(vim.inspect(report), "\n", { plain = true })

  if recordSnapshots or not exists then
    vim.fn.writefile(result, expectedResultPath)
  end

  return expectedResult, result
end

describe("ensure xcodebuild logs are processed correctly", function()
  --
  -- tests passed
  --
  describe("when tests passed", function()
    it("should set list of tests with correct data", function()
      local expectedResult, result = runTestCase(5)
      assert.are.same(expectedResult, result)
    end)
  end)

  --
  -- tests failed
  --
  describe("when tests failed", function()
    it("should set failed test message, lineNumber, and update counter", function()
      local expectedResult, result = runTestCase(10)
      assert.are.same(expectedResult, result)
    end)

    it("should set 2 warnings and 2 tests failed", function()
      local expectedResult, result = runTestCase(15)
      assert.are.same(expectedResult, result)
    end)
  end)

  --
  -- tests crashed
  --
  describe("when tests crashed in a different file than test file", function()
    it("should fill 5 diagnostics & set fail lineNumber at test header", function()
      local expectedResult, result = runTestCase(1)
      assert.are.same(expectedResult, result)
    end)

    it("should fill 3 diagnostics & set fail lineNumber at test header", function()
      local expectedResult, result = runTestCase(4)
      assert.are.same(expectedResult, result)
    end)
  end)

  --
  -- build succeeded
  --
  describe("when build passed", function()
    describe("when warnings are available", function()
      it("should set 3 warnings", function()
        local expectedResult, result = runTestCase(13)
        assert.are.same(expectedResult, result)
      end)

      it("should set 2 warnings", function()
        local expectedResult, result = runTestCase(14)
        assert.are.same(expectedResult, result)
      end)
    end)
  end)

  --
  -- build failure
  --
  describe("when build failed", function()
    describe("because of platform version incomatibility", function()
      it("should set build errors", function()
        local expectedResult, result = runTestCase(2)
        assert.are.same(expectedResult, result)
      end)
    end)

    describe("because of typo in code", function()
      it("should set build errors", function()
        local expectedResult, result = runTestCase(3)
        assert.are.same(expectedResult, result)
      end)
    end)

    describe("because of incorrect platform in Package.swift", function()
      it("should set build errors", function()
        local expectedResult, result = runTestCase(6)
        assert.are.same(expectedResult, result)
      end)
    end)

    describe("because of linter violation", function()
      it("should set build errors", function()
        local expectedResult, result = runTestCase(7)
        assert.are.same(expectedResult, result)
      end)
    end)

    describe("because of Info.plist incorrect structure", function()
      it("should set build errors", function()
        local expectedResult, result = runTestCase(8)
        assert.are.same(expectedResult, result)
      end)
    end)

    describe("because of incorrect version of dependency", function()
      it("should set build errors", function()
        local expectedResult, result = runTestCase(9)
        assert.are.same(expectedResult, result)
      end)
    end)
  end)

  --
  -- auto generated test plan
  --
  describe("when the project is using auto-generated test plan", function()
    describe("when tests failed", function()
      it("should parse test results", function()
        local expectedResult, result = runTestCase(11)
        assert.are.same(expectedResult, result)
      end)
    end)

    describe("when tests passed", function()
      it("should parse test results", function()
        local expectedResult, result = runTestCase(12)
        assert.are.same(expectedResult, result)
      end)
    end)
  end)

  --
  -- fresh project
  --
  describe("when the project is newly created with tests", function()
    it("should parse test results", function()
      local expectedResult, result = runTestCase(16)
      assert.are.same(expectedResult, result)
    end)
  end)
end)
