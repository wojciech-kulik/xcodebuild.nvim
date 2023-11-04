local M = {}

local util = require("xcodebuild.util")
local appdata = require("xcodebuild.appdata")

local add_summary_header = function(output)
	table.insert(output, "-----------------------------")
	table.insert(output, "-- xcodebuild.nvim summary --")
	table.insert(output, "-----------------------------")
	table.insert(output, "")
end

function M.show_tests_progress(report, firstChunk)
	if not next(report.tests) then
		if firstChunk then
			vim.print("Building Project...")
		end
	else
		vim.cmd(
			"echo 'Running Tests [Executed: " .. report.testsCount .. ", Failed: " .. report.failedTestsCount .. "]'"
		)
	end
end

function M.print_tests_summary(report)
	if report.testsCount == 0 then
		vim.print("Tests Failed [Executed: 0]")
	else
		vim.print(
			report.failedTestsCount == 0 and "All Tests Passed [Executed: " .. report.testsCount .. "]"
				or "Tests Failed [Executed: " .. report.testsCount .. ", Failed: " .. report.failedTestsCount .. "]"
		)
	end
end

function M.set_logs(report, isTesting, show)
	appdata.write_original_logs(report.output)
	local logs_filepath = appdata.get_original_logs_filepath()
	local prettyOutput = util.shell("cat '" .. logs_filepath .. "' | xcbeautify --disable-colored-output")

	add_summary_header(prettyOutput)
	M.set_warnings(prettyOutput, report.warnings)

	if report.buildErrors and report.buildErrors[1] then
		M.set_errors(prettyOutput, report.buildErrors)
	elseif isTesting then
		M.set_test_results(report, prettyOutput)
	else
		table.insert(prettyOutput, "  ✔ Build Succeeded")
		table.insert(prettyOutput, "")
	end

	vim.fn.writefile(prettyOutput, appdata.get_build_logs_filepath())

	M.update_panel(show)
end

function M.set_test_results(report, prettyOutput)
	M.print_tests_summary(report)

	if report.failedTestsCount > 0 then
		table.insert(prettyOutput, "Failing Tests:")
		for _, testsPerClass in pairs(report.tests) do
			for _, test in ipairs(testsPerClass) do
				if not test.success then
					local message = "    ✖ " .. test.class .. "." .. test.name
					if test.lineNumber then
						message = message .. ":" .. test.lineNumber
					end
					table.insert(prettyOutput, message)
				end
			end
		end
		table.insert(prettyOutput, "")
	else
		table.insert(prettyOutput, "  ✔ All " .. report.testCount .. " Tests Passed")
		table.insert(prettyOutput, "")
	end
end

function M.set_warnings(prettyOutput, warnings)
	if not warnings or not next(warnings) then
		return
	end

	table.insert(prettyOutput, "Warnings:")

	for _, warning in ipairs(warnings) do
		if warning.filepath then
			table.insert(
				prettyOutput,
				"   " .. warning.filepath .. ":" .. warning.lineNumber .. ":" .. (warning.columnNumber or 0)
			)
		end

		for index, message in ipairs(warning.message) do
			table.insert(
				prettyOutput,
				(index == 1 and not warning.filepath) and "   " .. message or "    " .. message
			)
		end
	end

	table.insert(prettyOutput, "")
end

function M.set_errors(prettyOutput, buildErrors)
	vim.print("Build Failed [" .. #buildErrors .. " error(s)]")
	table.insert(prettyOutput, "Errors:")

	for _, error in ipairs(buildErrors) do
		if error.filepath then
			table.insert(
				prettyOutput,
				"  ✖ " .. error.filepath .. ":" .. error.lineNumber .. ":" .. error.columnNumber
			)
		end

		for index, message in ipairs(error.message) do
			table.insert(prettyOutput, (index == 1 and not error.filepath) and "  ✖ " .. message or "    " .. message)
		end
	end
	table.insert(prettyOutput, "")
	table.insert(prettyOutput, "  ✖ Build Failed")
	table.insert(prettyOutput, "")
end

function M.update_panel(show)
	local testBufferName = appdata.get_build_logs_filename()
	local testBuffer = util.get_buf_by_name(testBufferName)

	if show then
		if testBuffer and not next(vim.fn.win_findbuf(testBuffer)) then
			vim.cmd("bo split | resize 20 | b " .. testBuffer)
		elseif not testBuffer then
			vim.cmd("bo split " .. appdata.get_build_logs_filepath() .. " | resize 20")
		end
	end

	if not show and not testBuffer then
		return
	end

	testBuffer = testBuffer or 0

	util.focus_buffer(testBuffer)
	vim.api.nvim_buf_set_option(testBuffer, "modifiable", true)
	vim.api.nvim_buf_set_option(testBuffer, "readonly", false)

	vim.cmd("e! | execute 'norm G'")

	vim.api.nvim_buf_set_option(testBuffer, "modifiable", false)
	vim.api.nvim_buf_set_option(testBuffer, "readonly", true)
end

function M.toggle_logs()
	local testBufferName = appdata.get_build_logs_filename()
	local testBuffer = util.get_buf_by_name(testBufferName, { returnNotLoaded = true })

	local logsFilepath = appdata.get_build_logs_filepath()
	if not testBuffer and vim.fn.readfile(logsFilepath) then
		vim.cmd("bo split " .. logsFilepath .. " | resize 20 ")
		return
	end

	local win = vim.fn.win_findbuf(testBuffer)[1]
	if win then
		vim.api.nvim_win_close(win, true)
	else
		vim.cmd("bo split | resize 20 | b " .. testBuffer)
		util.focus_buffer(testBuffer)
	end
end

function M.refresh_diagnostics(bufnr, testClass, report)
	if not report.tests then
		return
	end

	local ns = vim.api.nvim_create_namespace("xcodebuild-diagnostics")
	local diagnostics = {}
	local duplicates = {}

	for _, test in ipairs(report.tests[testClass] or {}) do
		if
			not test.success
			and test.filepath
			and test.lineNumber
			and not duplicates[test.filepath .. test.lineNumber]
		then
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
	local successSign = "✔"
	local failureSign = "✖"
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
		local mark = test.time and { "(" .. test.time .. ")", test.success and "DiagnosticWarn" or "DiagnosticError" }
			or { "" }

		if test.filepath and lineNumber then
			vim.api.nvim_buf_set_extmark(bufnr, ns, lineNumber, 0, {
				virt_text = { mark },
				sign_text = test.success and successSign or failureSign,
				sign_hl_group = test.success and "DiagnosticSignOk" or "DiagnosticSignError",
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

function M.open_test_file(tests)
	if not tests then
		return
	end

	local currentLine = vim.api.nvim_get_current_line()
	local testClass, testName, line = string.match(currentLine, "(%w*)%.(.*)%:(%d+)")

	for _, test in ipairs(tests[testClass] or {}) do
		if test.name == testName and test.filepath then
			vim.cmd("wincmd p | e " .. test.filepath .. " | " .. line)
			return
		end
	end
end

return M
