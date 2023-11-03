local util = require("xcodebuild.util")

local M = {}

local set_build_errors = function(list, errors)
	local duplicates = {}

	for _, error in ipairs(errors or {}) do
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

local set_failing_tests = function(list, tests)
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

local set_diagnostics_for_test_errors = function(list, diagnostics)
	local allSwiftFiles = util.find_all_swift_files2()
	for _, diagnostic in ipairs(diagnostics) do
		for _, filepath in ipairs(allSwiftFiles) do
			local filepathPattern = string.gsub(diagnostic.filepath, "/", "/.*/")
			filepathPattern = string.gsub(filepathPattern, "Tests/", "/")
			if string.find(filepath, filepathPattern) then
				diagnostic.filepath = filepath
				diagnostic.filename = util.get_filename(filepath)

				table.insert(list, {
					filename = filepath,
					lnum = diagnostic.lineNumber,
					text = diagnostic.message[1],
					type = "E",
				})
			end
		end
	end
end

function M.set(report)
	if not report.tests then
		vim.print("Missing xcode tests")
		return
	end

	local quickfix = {}
	set_build_errors(quickfix, report.buildErrors)
	set_failing_tests(quickfix, report.tests)
	set_diagnostics_for_test_errors(quickfix, report.diagnostics)

	vim.fn.setqflist(quickfix, "r")
end

return M
