local util = require("xcodebuild.util")

local M = {}

local function set_build_errors(list, errors)
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

local function set_failing_tests(list, tests)
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

local function set_warnings(list, warnings)
	for _, warning in ipairs(warnings) do
		if warning.filepath and warning.lineNumber then
			table.insert(list, {
				filename = warning.filepath,
				lnum = warning.lineNumber,
				col = warning.columnNumber or 0,
				text = warning.message[1],
				type = "W",
			})
		end
	end
end

local function set_diagnostics_for_test_errors(list, diagnostics)
	local allSwiftFiles = util.find_all_swift_files()

	for _, diagnostic in ipairs(diagnostics) do
		for _, filepath in pairs(allSwiftFiles) do
			-- Errors are returned like "{target}/{filename}", for example: "MyProjectTests/Mocks.swift"
			-- We are trying to find a real path based on that.
			-- The code below assumes that the path should match "MyProject/.*/Mocks.swift"
			-- In general, those errors occur only when the code is crashing during tests.
			-- TODO: This code may not be accurate when the target is named differently than the folder. Also, the pattern could match some other place.
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
	local quickfix = {}

	set_build_errors(quickfix, report.buildErrors or {})
	set_warnings(quickfix, report.warnings or {})
	set_failing_tests(quickfix, report.tests or {})
	set_diagnostics_for_test_errors(quickfix, report.diagnostics or {})

	vim.fn.setqflist(quickfix, "r")
end

return M
