local ui = require("xcodebuild.ui")
local parser = require("xcodebuild.parser")
local util = require("xcodebuild.util")
local xchelper = require("xcodebuild.xchelper")

local M = {}
local autogroup = vim.api.nvim_create_augroup("xctest", { clear = true })
local testReport = {}

function M.setup()
	vim.api.nvim_create_user_command("Test", function(opts)
		local deviceId = xchelper.get_booted_device_id()
		local success, projectScheme = pcall(xchelper.get_project_scheme)
		if not success then
			vim.print("Scheme not found. Tests cancelled.")
			return
		end

		local project = "Project.xcodeproj"
		local testPlan = "TestPlan"
		local command = "xcodebuild test -scheme "
			.. projectScheme
			.. " -destination 'id="
			.. deviceId
			.. "' -project "
			.. project
			.. " -testPlan "
			.. testPlan

		vim.print("Starting Tests...")
		local on_exit = function()
			ui.show_logs(testReport)

			if not testReport.buildErrors or not testReport.buildErrors[1] then
				ui.print_summary(testReport)
				ui.set_quickfix(testReport)
				ui.refresh_buf_diagnostics(testReport)
			end
			vim.fn.writefile(testReport.output, "/tmp/xctest.log")
		end

		if opts.fargs[1] == "last" then
			local log = vim.fn.readfile("/tmp/xctest.log")
			parser.clear()
			testReport = parser.parse_logs(log)
			on_exit()
		elseif opts.fargs[1] == "debug" then
			for i = 1, 10 do
				local log = vim.fn.readfile("/Users/wkulik/Desktop/tests/tc" .. i .. ".log")
				parser.clear()
				testReport = parser.parse_logs(log)
				testReport.output = {}
				vim.fn.writefile(
					vim.split(vim.inspect(testReport), "\n", { plain = true }),
					"/Users/wkulik/Desktop/tests/tc" .. i .. "_out.log"
				)
			end
			vim.print("FINISHED")
		else
			local isFirstChunk = true

			vim.cmd("silent wa!")
			vim.fn.jobstart(command, {
				stdout_buffered = false,
				stderr_buffered = false,
				on_stdout = function(_, output)
					if isFirstChunk then
						parser.clear()
					end
					testReport = parser.parse_logs(output)
					ui.show_progress(testReport, isFirstChunk)
					ui.refresh_buf_diagnostics(testReport)
					isFirstChunk = false
				end,
				on_stderr = function(_, output)
					if isFirstChunk then
						parser.clear()
						isFirstChunk = false
					end
					testReport = parser.parse_logs(output)
				end,
				on_exit = on_exit,
			})
		end
	end, { nargs = "*" })

	vim.api.nvim_set_keymap("n", "dx", "", {
		callback = function()
			ui.toggle_logs()
		end,
	})

	vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
		group = autogroup,
		pattern = "*xcode-tests.log",
		callback = function(ev)
			vim.api.nvim_set_option_value("filetype", "objc", { buf = ev.buf })
			vim.api.nvim_set_option_value("wrap", false, { buf = ev.buf })
			vim.api.nvim_set_option_value("spell", false, { buf = ev.buf })

			vim.api.nvim_buf_set_keymap(ev.buf, "n", "q", "<cmd>close<cr>", {})
			vim.api.nvim_buf_set_keymap(ev.buf, "n", "o", "", {
				callback = function()
					ui.open_test_file(testReport.tests)
				end,
			})
		end,
	})

	vim.api.nvim_create_autocmd({ "BufReadPost" }, {
		group = autogroup,
		pattern = "*Tests.swift",
		callback = function(ev)
			if testReport then
				local testClass = util.get_filename(ev.file)
				ui.refresh_diagnostics(ev.buf, testClass, testReport)
				ui.set_buf_marks(ev.buf, testClass, testReport.tests)
			end
		end,
	})
end

-- M.setup()

return M
