local M = {}

local util = require("xcodebuild.util")

function M.show_progress(report, firstChunk)
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

function M.print_summary(report)
	if report.testsCount == 0 then
		vim.print("Tests Failed [Executed: 0]")
	else
		vim.print(
			report.failedTestsCount == 0 and "All Tests Succeeded [Executed: " .. report.testsCount .. "]"
				or "Tests Failed [Executed: " .. report.testsCount .. ", Failed: " .. report.failedTestsCount .. "]"
		)
	end
end

function M.show_logs(report)
	local output = report.output

	if not output then
		vim.print("Missing xcode test output")
		return
	end

	vim.fn.writefile(output, "/tmp/logs.txt")
	local pretty = util.shell("cat /tmp/logs.txt | xcbeautify --disable-colored-output")
	local prettyOutput = vim.split(pretty, "\n", { plain = true })
	util.shell("rm -f /tmp/logs.txt")

	if report.buildErrors and report.buildErrors[1] then
		M.show_error_logs(prettyOutput, report.buildErrors)
	else
		M.show_test_logs(report, prettyOutput)
	end
end

function M.show_test_logs(report, prettyOutput)
	local failedTestsSummary = {}

	if report.failedTestsCount > 0 then
		table.insert(failedTestsSummary, "Failing Tests:")
		for _, testsPerClass in pairs(report.tests) do
			for _, test in ipairs(testsPerClass) do
				if not test.success then
					local message = "    ✖ " .. test.class .. "." .. test.name
					if test.lineNumber then
						message = message .. ":" .. test.lineNumber
					end
					table.insert(failedTestsSummary, message)
				end
			end
		end
		table.insert(failedTestsSummary, "")
	end

	local summary = util.merge_array(prettyOutput, failedTestsSummary)
	M.show_panel(summary)
end

function M.show_error_logs(prettyOutput, buildErrors)
	vim.print("Build Failed [" .. #buildErrors .. " error(s)]")
	table.insert(prettyOutput, "--------------------------")
	table.insert(prettyOutput, "")
	table.insert(prettyOutput, "Build Errors:")
	for _, error in ipairs(buildErrors) do
		if error.filepath then
			table.insert(
				prettyOutput,
				" ✖ " .. error.filepath .. ":" .. error.lineNumber .. ":" .. error.columnNumber
			)
		end

		for index, message in ipairs(error.message) do
			table.insert(prettyOutput, (index == 1 and not error.filepath) and " ✖ " .. message or message)
		end
	end

	M.show_panel(prettyOutput)
end

function M.show_panel(lines)
	local testBufferName = "xcode-tests.log"
	local testBuffer = util.get_buf_by_name(testBufferName)

	util.shell("mkdir -p logs")

	if testBuffer and not next(vim.fn.win_findbuf(testBuffer)) then
		vim.cmd("horizontal sb | b " .. testBuffer .. " | resize 20")
	elseif not testBuffer then
		vim.cmd("new")
		vim.api.nvim_win_set_height(0, 20)
		vim.api.nvim_buf_set_name(0, "logs/" .. testBufferName)
	end

	util.focus_buffer(testBuffer or 0)
	vim.api.nvim_buf_set_lines(testBuffer or 0, 0, -1, false, lines)
	vim.api.nvim_win_set_cursor(0, { #lines, 0 })
	vim.cmd("silent update!")
end

function M.toggle_logs()
	local testBufferName = "xcode-tests.log"
	local testBuffer = util.get_buf_by_name(testBufferName, { returnNotLoaded = true })

	if not testBuffer then
		return
	end

	local win = vim.fn.win_findbuf(testBuffer)[1]
	if win then
		vim.api.nvim_win_close(win, true)
	else
		vim.cmd("horizontal sb | b " .. testBuffer .. " | resize 20")
		util.focus_buffer(testBuffer)
	end
end

function M.set_quickfix(report)
	if not report.tests then
		vim.print("Missing xcode tests")
		return
	end

	local quickfix = {}

	for _, testsPerClass in pairs(report.tests) do
		for _, test in ipairs(testsPerClass) do
			if not test.success and test.filepath and test.lineNumber then
				table.insert(quickfix, {
					filename = test.filepath,
					lnum = test.lineNumber,
					text = test.message[1],
					type = "E",
				})
			end
		end
	end

	local allSwiftFiles = util.find_all_swift_files2()
	for _, diagnostic in ipairs(report.diagnostics) do
		for _, filepath in ipairs(allSwiftFiles) do
			local filepathPattern = string.gsub(diagnostic.filepath, "/", "/.*/")
			filepathPattern = string.gsub(filepathPattern, "Tests/", "/")
			if string.find(filepath, filepathPattern) then
				diagnostic.filepath = filepath
				diagnostic.filename = util.get_filename(filepath)

				table.insert(quickfix, {
					filename = filepath,
					lnum = diagnostic.lineNumber,
					text = diagnostic.message[1],
					type = "E",
				})
			end
		end
	end

	vim.fn.setqflist(quickfix, "r")
end

function M.refresh_diagnostics(bufnr, testClass, report)
	if not report.tests then
		return
	end

	local ns = vim.api.nvim_create_namespace("xcodebuild-diagnostics")
	local diagnostics = {}

	for _, test in ipairs(report.tests[testClass] or {}) do
		if not test.success and test.filepath and test.lineNumber then
			table.insert(diagnostics, {
				bufnr = bufnr,
				lnum = test.lineNumber - 1,
				col = 0,
				severity = vim.diagnostic.severity.ERROR,
				source = "xcodebuild",
				message = table.concat(test.message, "\n"),
				user_data = {},
			})
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
			vim.cmd("e " .. test.filepath .. " | " .. line)
			return
		end
	end
end

return M
