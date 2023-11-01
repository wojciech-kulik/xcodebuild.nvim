local M = {}

local util = require("xcodebuild.util")

-- state machine
local BEGIN = "BEGIN"
local TEST_START = "TEST_START"
local TEST_ERROR = "TEST_ERROR"
local BUILD_ERROR = "BUILD_ERROR"

-- temp fields
local allSwiftFiles = {}
local lineType = BEGIN
local lineData = {}
local lastTest = nil

-- report fields
local testsCount = 0
local tests = {}
local failedTestsCount = 0
local output = {}
local buildErrors = {}
local diagnostics = {}

local flush_test = function(message)
	if message then
		table.insert(lineData.message, message)
	end

	tests[lineData.class] = tests[lineData.class] or {}
	table.insert(tests[lineData.class], lineData)
	lastTest = lineData
	lineType = BEGIN
	lineData = {}
end

local flush_error = function(line)
	if line then
		table.insert(lineData.message, line)
	end

	table.insert(buildErrors, lineData)
	lineType = BEGIN
	lineData = {}
end

local flush_diagnostic = function(filepath, filename, lineNumber)
	table.insert(diagnostics, {
		filepath = filepath,
		filename = filename,
		lineNumber = lineNumber,
		message = lineData.message,
	})
end

local sanitize = function(message)
	return string.match(message, "%-%[%w+%.%w+ %g+%] %: (.*)") or message
end

local find_test_line = function(filepath, testName)
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

local parse_build_error = function(line)
	if string.find(line, "[^%s]*%.swift%:%d+%:%d*%:? %w*%s*error%: .*") then
		local filepath, lineNumber, colNumber, message =
			string.match(line, "([^%s]*%.swift)%:(%d+)%:(%d*)%:? %w*%s*error%: (.*)")
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

local parse_test_error = function(line)
	failedTestsCount = failedTestsCount + 1

	local filepath, lineNumber, message = string.match(line, "([^%s]*%.swift)%:(%d+)%:%d*%:? %w*%s*error%: (.*)")

	if filepath and message then
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

local parse_test_finished = function(line)
	local testResult, time = string.match(line, "^Test Case .*.%-%[%w+%.%w+ %g+%]. (%w+)% %((.*)%)%.")
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
end

local parse_test_started = function(line)
	local testClass, testName = string.match(line, "^Test Case .*.%-%[%w+%.(%w+) (%g+)%]")
	if not allSwiftFiles[testClass] then
		vim.print(testClass)
	end
	testsCount = testsCount + 1
	lastTest = nil
	lineType = TEST_START
	lineData = {
		filepath = allSwiftFiles[testClass],
		filename = util.get_filename(allSwiftFiles[testClass]),
		class = testClass,
		name = testName,
	}
end

local process_line = function(line)
	table.insert(output, line)

	-- POSSIBLE PATHS:
	-- BEGIN -> BUILD_ERROR -> BEGIN
	-- BEGIN -> TEST_START -> passed -> BEGIN
	-- BEGIN -> TEST_START -> TEST_ERROR -> (failed) -> BEGIN

	if string.find(line, "^Test Case.*started%.") then
		parse_test_started(line)
	elseif string.find(line, "^Test Case.*passed") or string.find(line, "^Test Case.*failed") then
		parse_test_finished(line)
	elseif string.find(line, "error%:") then
		if lineType == BUILD_ERROR then
			flush_error()
		end

		if lineType == TEST_START then
			parse_test_error(line)
		elseif testsCount == 0 and lineType == BEGIN then
			parse_build_error(line)
		end
	elseif lineType == BUILD_ERROR and string.find(line, "^%s*$") then
		flush_error()
	elseif lineType == TEST_ERROR and string.find(line, "^%s*$") then
		flush_test()
	elseif lineType == BUILD_ERROR and (string.find(line, "^Linting") or string.find(line, "^note%:")) then
		flush_error()
	elseif lineType == BUILD_ERROR and string.find(line, "%s*~*%^~*%s*") then
		flush_error(line)
	elseif lineType == TEST_ERROR and string.find(line, "%s*~*%^~*%s*") then
		flush_test(line)
	elseif lineType == TEST_ERROR or lineType == BUILD_ERROR then
		table.insert(lineData.message, line)
	end
end

function M.clear()
	lastTest = nil
	lineData = {}
	lineType = BEGIN
	allSwiftFiles = util.find_all_swift_files()

	tests = {}
	testsCount = 0
	failedTestsCount = 0
	output = {}
	buildErrors = {}
	diagnostics = {}
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
		diagnostics = diagnostics,
	}
end

return M
