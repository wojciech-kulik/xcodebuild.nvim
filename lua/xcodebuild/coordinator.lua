local ui = require("xcodebuild.ui")
local parser = require("xcodebuild.parser")
local util = require("xcodebuild.util")
local appdata = require("xcodebuild.appdata")
local quickfix = require("xcodebuild.quickfix")
local config = require("xcodebuild.config")
local xcode = require("xcodebuild.xcode")

local M = {}
local testReport = {}

function M.get_report()
	return testReport
end

function M.setup_log_buffer(bufnr)
	local win = vim.fn.win_findbuf(bufnr)[1]
	vim.api.nvim_win_set_option(win, "wrap", false)
	vim.api.nvim_win_set_option(win, "spell", false)
	vim.api.nvim_buf_set_option(bufnr, "filetype", "objc")
	vim.api.nvim_buf_set_option(bufnr, "buflisted", false)
	vim.api.nvim_buf_set_option(bufnr, "fileencoding", "utf-8")
	vim.api.nvim_buf_set_option(bufnr, "readonly", true)
	vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
	vim.api.nvim_buf_set_option(bufnr, "modified", false)

	vim.api.nvim_buf_set_keymap(bufnr, "n", "q", "<cmd>close<cr>", {})
	vim.api.nvim_buf_set_keymap(bufnr, "n", "o", "", {
		callback = function()
			ui.open_test_file(testReport.tests)
		end,
	})
end

function M.load_last_report()
	local success, log = pcall(appdata.read_original_logs)
	if success then
		parser.clear()
		testReport = parser.parse_logs(log)
		quickfix.set(testReport)
	end
end

function M.refresh_buf_diagnostics(bufnr, file)
	local testClass = util.get_filename(file)
	ui.refresh_diagnostics(bufnr, testClass, testReport)
	ui.set_buf_marks(bufnr, testClass, testReport.tests)
end

function M.build_and_install_app(callback)
	appdata.create_app_dir()
	config.load_settings()

	M.build_project({
		open_logs_on_success = false,
	}, function(report)
		local destination = config.settings().destination
		local target = config.settings().appTarget
		local settings = xcode.get_app_settings(report.output)

		if target then
			xcode.kill_app(target)
		end

		config.settings().appPath = settings.appPath
		config.settings().appTarget = settings.targetName
		config.settings().bundleId = settings.bundleId
		config.save_settings()

		xcode.install_app(destination, settings.appPath, function()
			xcode.launch_app(destination, settings.bundleId, function()
				callback()
			end)
		end)
	end)
end

function M.build_project(opts, callback)
	appdata.create_app_dir()
	config.load_settings()

	local open_logs_on_success = (opts or {}).open_logs_on_success
	vim.print("Building...")
	vim.cmd("silent wa!")
	parser.clear()

	local on_stdout = function(_, output)
		testReport = parser.parse_logs(output)

		if testReport.buildErrors and testReport.buildErrors[1] then
			vim.cmd("echo 'Building... [Errors: " .. #testReport.buildErrors .. "]'")
		end
	end

	local on_stderr = function(_, output)
		testReport = parser.parse_logs(output)
	end

	local on_exit = function()
		ui.set_logs(testReport, false, open_logs_on_success)
		if not testReport.buildErrors or not testReport.buildErrors[1] then
			vim.print("Build Succeeded")
		end
		quickfix.set(testReport)
		callback(testReport)
	end

	xcode.build_project({
		on_exit = on_exit,
		on_stdout = on_stdout,
		on_stderr = on_stderr,

		destination = config.settings().destination,
		projectCommand = config.settings().projectCommand,
		scheme = config.settings().scheme,
		testPlan = config.settings().testPlan,
	})
end

function M.run_tests()
	appdata.create_app_dir()
	config.load_settings()

	vim.print("Starting Tests...")
	vim.cmd("silent wa!")
	parser.clear()

	local isFirstChunk = true
	local on_stdout = function(_, output)
		testReport = parser.parse_logs(output)
		ui.show_tests_progress(testReport, isFirstChunk)
		ui.refresh_buf_diagnostics(testReport)
		isFirstChunk = false
	end

	local on_stderr = function(_, output)
		isFirstChunk = false
		testReport = parser.parse_logs(output)
	end

	local on_exit = function()
		ui.set_logs(testReport, true, true)
		quickfix.set(testReport)
		ui.refresh_buf_diagnostics(testReport)
	end

	xcode.run_tests({
		on_exit = on_exit,
		on_stdout = on_stdout,
		on_stderr = on_stderr,

		destination = config.settings().destination,
		projectCommand = config.settings().projectCommand,
		scheme = config.settings().scheme,
		testPlan = config.settings().testPlan,
	})
end

function M.configure_project()
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
end

return M
