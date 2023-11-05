local M = {}

local ui = require("xcodebuild.ui")
local util = require("xcodebuild.util")
local appdata = require("xcodebuild.appdata")

local function add_summary_header(output)
	table.insert(output, "-----------------------------")
	table.insert(output, "-- xcodebuild.nvim summary --")
	table.insert(output, "-----------------------------")
	table.insert(output, "")
end

function M.set_logs(report, isTesting, show)
	appdata.write_original_logs(report.output)
	local logs_filepath = appdata.get_original_logs_filepath()
	local command = "cat '" .. logs_filepath .. "' | xcbeautify --disable-colored-output"

	vim.fn.jobstart(command, {
		stdout_buffered = true,
		on_stdout = function(_, prettyOutput)
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
			M.update_log_panel(show)
		end,
	})
end

function M.set_test_results(report, prettyOutput)
	ui.print_tests_summary(report)

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
		table.insert(prettyOutput, "  ✖ " .. report.failedTestsCount .. " Test(s) Failed")
		table.insert(prettyOutput, "")
	else
		table.insert(prettyOutput, "  ✔ All Tests Passed [Executed: " .. report.testsCount .. "]")
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
	vim.notify("Build Failed [" .. #buildErrors .. " error(s)]", vim.log.levels.ERROR)
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

function M.update_log_panel(show)
	local logsFilepath = appdata.get_build_logs_filepath()
	local bufnr = util.get_buf_by_name(appdata.get_build_logs_filename(), { returnNotLoaded = true }) or -1
	local winnr = vim.fn.win_findbuf(bufnr)[1]

	if show then
		if winnr then
			util.focus_buffer(bufnr)
		elseif vim.fn.filereadable(logsFilepath) then
			vim.cmd("silent bo split " .. logsFilepath .. " | resize 20")
			local numberOfLines = #vim.api.nvim_buf_get_lines(0, 0, -1, false)
			vim.api.nvim_win_set_cursor(0, { numberOfLines, 0 })
			bufnr = 0
			winnr = 0
		end
	end

	if bufnr == -1 then
		return
	end

	vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
	vim.api.nvim_buf_set_option(bufnr, "readonly", false)

	if winnr then
		vim.cmd("silent e!")
		local linesNumber = #vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
		vim.api.nvim_win_set_cursor(winnr, { linesNumber, 0 })
	end

	vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
	vim.api.nvim_buf_set_option(bufnr, "readonly", true)
end

function M.open_logs(forceScroll, focus)
	local logsFilepath = appdata.get_build_logs_filepath()
	local bufnr = util.get_buf_by_name(appdata.get_build_logs_filename(), { returnNotLoaded = true }) or -1
	local winnr = vim.fn.win_findbuf(bufnr)[1]

	if winnr then
		if focus then
			util.focus_buffer(bufnr)
		end
		return
	end

	vim.cmd("bo split " .. logsFilepath .. " | resize 20")
	if not focus then
		vim.cmd("wincmd p")
	end

	if bufnr == -1 or forceScroll then -- new buffer should be scrolled
		local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
		vim.api.nvim_win_set_cursor(0, { #lines, 0 })
	end
end

function M.close_logs()
	local bufnr = util.get_buf_by_name(appdata.get_build_logs_filename(), { returnNotLoaded = true }) or -1
	local winnr = vim.fn.win_findbuf(bufnr)[1]

	if winnr then
		vim.api.nvim_win_close(winnr, true)
	end
end

function M.toggle_logs()
	local bufnr = util.get_buf_by_name(appdata.get_build_logs_filename(), { returnNotLoaded = true }) or -1
	local winnr = vim.fn.win_findbuf(bufnr)[1]

	if winnr then
		M.close_logs()
	else
		M.open_logs(false, true)
	end
end

return M
