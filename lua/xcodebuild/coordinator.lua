local ui = require("xcodebuild.ui")
local parser = require("xcodebuild.parser")
local util = require("xcodebuild.util")
local appdata = require("xcodebuild.appdata")
local quickfix = require("xcodebuild.quickfix")
local config = require("xcodebuild.config")
local xcode = require("xcodebuild.xcode")
local logs = require("xcodebuild.logs")
local diagnostics = require("xcodebuild.diagnostics")

local M = {}
local testReport = {}
local currentJobId = nil
local targetToFiles = {}

local function update_settings(output)
	local settings = xcode.get_app_settings(output)
	config.settings().appPath = settings.appPath
	config.settings().appTarget = settings.targetName
	config.settings().bundleId = settings.bundleId
	config.save_settings()
end

function M.cancel()
	if currentJobId then
		vim.fn.jobstop(currentJobId)
		currentJobId = nil
		vim.notify("Stopped")
	end
end

function M.get_report()
	return testReport
end

function M.setup_log_buffer(bufnr)
	local win = vim.fn.win_findbuf(bufnr)[1]
	vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
	vim.api.nvim_buf_set_option(bufnr, "readonly", false)

	vim.api.nvim_win_set_option(win, "wrap", false)
	vim.api.nvim_win_set_option(win, "spell", false)
	vim.api.nvim_buf_set_option(bufnr, "filetype", "objc")
	vim.api.nvim_buf_set_option(bufnr, "buflisted", false)
	vim.api.nvim_buf_set_option(bufnr, "fileencoding", "utf-8")
	vim.api.nvim_buf_set_option(bufnr, "modified", false)

	vim.api.nvim_buf_set_option(bufnr, "readonly", true)
	vim.api.nvim_buf_set_option(bufnr, "modifiable", false)

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
	diagnostics.refresh_diagnostics(bufnr, testClass, testReport)
	diagnostics.set_buf_marks(bufnr, testClass, testReport.tests)
end

function M.build_and_run_app(callback)
	M.build_project({
		open_logs_on_success = false,
	}, function(report)
		local settings = config.settings()
		local destination = settings.destination
		local target = settings.appTarget

		if report.buildErrors and report.buildErrors[1] then
			vim.notify("Build Failed", vim.log.levels.ERROR)
			logs.open_logs(true, true)
			return
		end

		if target then
			xcode.kill_app(target)
		end

		vim.notify("Installing application...")
		currentJobId = xcode.install_app(destination, settings.appPath, function()
			vim.notify("Launching application...")
			currentJobId = xcode.launch_app(destination, settings.bundleId, function()
				vim.notify("Application has been launched")
				if callback then
					callback()
				end
			end)
		end)
	end)
end

function M.build_project(opts, callback)
	local open_logs_on_success = (opts or {}).open_logs_on_success
	local build_for_testing = (opts or {}).build_for_testing

	vim.notify("Building...")
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

	local on_exit = function(_, code, _)
		if code == 143 then
			return
		end
		logs.set_logs(testReport, false, open_logs_on_success)
		if not testReport.buildErrors or not testReport.buildErrors[1] then
			update_settings(testReport.output)
			vim.notify("Build Succeeded")
		end
		quickfix.set(testReport)

		if callback then
			callback(testReport)
		end
	end

	currentJobId = xcode.build_project({
		on_exit = on_exit,
		on_stdout = on_stdout,
		on_stderr = on_stderr,

		build_for_testing = build_for_testing,
		destination = config.settings().destination,
		projectCommand = config.settings().projectCommand,
		scheme = config.settings().scheme,
		testPlan = config.settings().testPlan,
	})
end

function M.run_tests(testsToRun)
	vim.notify("Starting Tests...")
	vim.cmd("silent wa!")
	parser.clear()

	local isFirstChunk = true
	local on_stdout = function(_, output)
		testReport = parser.parse_logs(output)
		ui.show_tests_progress(testReport, isFirstChunk)
		diagnostics.refresh_buf_diagnostics(testReport)
		isFirstChunk = false
	end

	local on_stderr = function(_, output)
		isFirstChunk = false
		testReport = parser.parse_logs(output)
	end

	local on_exit = function(_, code, _)
		if code == 143 then
			return
		end

		update_settings(testReport.output)
		targetToFiles = xcode.get_targets_list(config.settings().appPath)
		logs.set_logs(testReport, true, true)
		quickfix.setTargets(targetToFiles)
		quickfix.set(testReport)
		diagnostics.refresh_buf_diagnostics(testReport)
	end

	currentJobId = xcode.run_tests({
		on_exit = on_exit,
		on_stdout = on_stdout,
		on_stderr = on_stderr,

		destination = config.settings().destination,
		projectCommand = config.settings().projectCommand,
		scheme = config.settings().scheme,
		testPlan = config.settings().testPlan,
		testsToRun = testsToRun,
	})
end

local function find_tests(opts)
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
	local selectedClass = nil
	local selectedTests = {}

	for _, line in ipairs(lines) do
		selectedClass = string.match(line, "class ([^:%s]+)%s*%:?")
		if selectedClass then
			break
		end
	end

	if opts.selectedTests then
		local vstart = vim.fn.getpos("'<")
		local vend = vim.fn.getpos("'>")
		local lineStart = vstart[2]
		local lineEnd = vend[2]

		for i = lineStart, lineEnd do
			local test = string.match(lines[i], "func (test[^%s%(]+)")
			if test then
				table.insert(selectedTests, {
					name = test,
					class = selectedClass,
				})
			end
		end
	elseif opts.currentTest then
		local winnr = vim.api.nvim_get_current_win()
		local currentLine = vim.api.nvim_win_get_cursor(winnr)[1]

		for i = currentLine, 1, -1 do
			local test = string.match(lines[i], "func (test[^%s%(]+)")
			if test then
				table.insert(selectedTests, {
					name = test,
					class = selectedClass,
				})
				break
			end
		end
	elseif opts.failingTests and testReport.failedTestsCount > 0 then
		for _, testsPerClass in pairs(testReport.tests) do
			for _, test in ipairs(testsPerClass) do
				if not test.success then
					table.insert(selectedTests, {
						name = test.name,
						class = test.class,
						filepath = test.filepath,
					})
				end
			end
		end
	end

	return selectedClass, selectedTests
end

local function find_target_for_file(filepath)
	for target, files in pairs(targetToFiles) do
		if util.contains(files, filepath) then
			return target
		end
	end
end

function M.run_selected_tests(opts)
	local selectedClass, selectedTests = find_tests(opts)

	local start = function()
		local testsToRun = {}
		local testFilepath = vim.api.nvim_buf_get_name(0)
		local target = find_target_for_file(testFilepath)

		if not target then
			vim.notify("Could not detect test target. Please run build again.")
			return
		end

		if opts.currentClass and selectedClass then
			table.insert(testsToRun, target .. "/" .. selectedClass)
		end

		if opts.currentTest or opts.selectedTests then
			for _, test in ipairs(selectedTests) do
				table.insert(testsToRun, target .. "/" .. test.class .. "/" .. test.name)
			end
		end

		if opts.failingTests then
			for _, test in ipairs(selectedTests) do
				local testTarget = find_target_for_file(test.filepath)
				if testTarget then
					table.insert(testsToRun, testTarget .. "/" .. test.class .. "/" .. test.name)
				end
			end
		end

		vim.print("Discovered tests: " .. vim.inspect(testsToRun))

		if next(testsToRun) then
			M.run_tests(testsToRun)
		else
			vim.notify("Tests not found", vim.log.levels.ERROR)
		end
	end

	if not targetToFiles or not next(targetToFiles) then
		vim.notify("Loading tests...")
		currentJobId = M.build_project({
			build_for_testing = true,
		}, function()
			targetToFiles = xcode.get_targets_list(config.settings().appPath)
			quickfix.setTargets(targetToFiles)
			start()
		end)
	else
		start()
	end
end

function M.configure_project()
	appdata.create_app_dir()
	local pickers = require("xcodebuild.pickers")
	local defer_print = function(text)
		vim.defer_fn(function()
			vim.notify(text)
		end, 100)
	end

	pickers.select_project(function()
		defer_print("Loading schemes...")
		pickers.select_scheme(function()
			defer_print("Loading devices...")
			pickers.select_destination(function()
				defer_print("Loading test plans...")
				pickers.select_testplan(function()
					defer_print("Xcodebuild configuration has been saved!")
				end, { close_on_select = true })
			end)
		end)
	end)
end

return M
