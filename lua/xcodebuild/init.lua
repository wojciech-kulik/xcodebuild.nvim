local ui = require("xcodebuild.ui")
local parser = require("xcodebuild.parser")
local util = require("xcodebuild.util")
local config = require("xcodebuild.config")
local xcode = require("xcodebuild.xcode")
local appdata = require("xcodebuild.appdata")

local M = {}
local autogroup = vim.api.nvim_create_augroup("xcodebuild.nvim", { clear = true })
local testReport = {}

function M.setup()
	vim.api.nvim_create_user_command("XcodebuildSetup", function()
		appdata.create_app_dir()

		require("xcodebuild.pickers").select_project(function()
			require("xcodebuild.pickers").select_scheme(function()
				require("xcodebuild.pickers").select_testplan(function()
					require("xcodebuild.pickers").select_destination(function()
						vim.defer_fn(function()
							vim.print("xcodebuild configuration has been saved!")
						end, 100)
					end)
				end)
			end)
		end)
	end, { nargs = 0 })

	vim.api.nvim_create_user_command("Build", function()
		appdata.create_app_dir()
		config.load_settings()
		local destination = config.settings().destination
		local projectCommand = config.settings().projectCommand
		local scheme = config.settings().scheme
		xcode.build_project(projectCommand, scheme, destination, function() end)
	end, { nargs = 0 })

	vim.api.nvim_create_user_command("Test", function(opts)
		appdata.create_app_dir()
		config.load_settings()
		local destination = config.settings().destination
		local projectCommand = config.settings().projectCommand
		local scheme = config.settings().scheme
		local testPlan = config.settings().testPlan
		local command = "xcodebuild test -scheme '"
			.. scheme
			.. "' -destination 'id="
			.. destination
			.. "' "
			.. projectCommand
			.. " -testPlan '"
			.. testPlan
			.. "'"

		vim.print("Starting Tests...")
		local on_exit = function()
			ui.show_logs(testReport)

			if not testReport.buildErrors or not testReport.buildErrors[1] then
				ui.print_summary(testReport)
				ui.set_quickfix(testReport)
				ui.refresh_buf_diagnostics(testReport)
			end
		end

		if opts.fargs[1] == "last" then
			local log = appdata.read_original_logs()
			parser.clear()
			testReport = parser.parse_logs(log)
			on_exit()
		elseif opts.fargs[1] == "debug" then
			for i = 1, 12 do
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

	vim.api.nvim_create_autocmd({ "BufReadPost" }, {
		group = autogroup,
		pattern = "*" .. appdata.get_build_logs_filename(),
		callback = function(ev)
			local win = vim.fn.win_findbuf(ev.buf)[1]
			vim.api.nvim_win_set_option(win, "wrap", false)
			vim.api.nvim_win_set_option(win, "spell", false)
			vim.api.nvim_buf_set_option(ev.buf, "filetype", "objc")
			vim.api.nvim_buf_set_option(ev.buf, "buflisted", false)
			vim.api.nvim_buf_set_option(ev.buf, "fileencoding", "utf-8")
			vim.api.nvim_buf_set_option(ev.buf, "readonly", true)
			vim.api.nvim_buf_set_option(ev.buf, "modifiable", false)
			vim.api.nvim_buf_set_option(ev.buf, "modified", false)

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

return M
