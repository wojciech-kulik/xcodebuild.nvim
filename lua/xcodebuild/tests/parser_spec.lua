local assert = require("luassert")
local parser = require("xcodebuild.parser")
local cwd = vim.fn.getcwd()

local mockSwiftFiles = function()
	local filetree = table.concat(vim.fn.readfile(cwd .. "/lua/xcodebuild/tests/test_data/file_tree.txt"), "\n")
	vim.fn.system = function()
		return filetree
	end
end

local runTestCase = function(caseId)
	local expectedResult = vim.fn.readfile(cwd .. "/lua/xcodebuild/tests/test_data/tc" .. caseId .. "_out.log")
	local log = vim.fn.readfile(cwd .. "/lua/xcodebuild/tests/test_data/tc" .. caseId .. ".log")
	mockSwiftFiles()
	parser.clear()

	local testReport = parser.parse_logs(log)
	testReport.output = {}
	local result = vim.split(vim.inspect(testReport), "\n", { plain = true })

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
end)
