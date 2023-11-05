local coordinator = require("xcodebuild.coordinator")
local pickers = require("xcodebuild.pickers")
local logs = require("xcodebuild.logs")

local M = {}

local function defer_print(text)
	vim.defer_fn(function()
		vim.notify(text)
	end, 100)
end

function M.show_logs()
	logs.open_logs(true, true)
end

function M.close_logs()
	logs.close_logs()
end

function M.toggle_logs()
	logs.toggle_logs()
end

function M.show_picker()
	pickers.show_all_actions()
end

function M.build(callback)
	coordinator.build_project({ open_logs_on_success = true }, callback)
end

function M.cancel()
	coordinator.cancel()
end

function M.configure_project()
	coordinator.configure_project()
end

function M.build_and_run(callback)
	coordinator.build_and_run_app(callback)
end

function M.run_tests()
	coordinator.run_tests()
end

function M.run_class_tests()
	coordinator.run_selected_tests({
		currentClass = true,
	})
end

function M.run_func_test()
	coordinator.run_selected_tests({
		currentTest = true,
	})
end

function M.run_selected_tests()
	coordinator.run_selected_tests({
		selectedTests = true,
	})
end

function M.run_failing_tests()
	coordinator.run_selected_tests({
		failingTests = true,
	})
end

function M.clear_tests_cache()
	coordinator.clear_tests_cache()
end

function M.select_project(callback)
	pickers.select_project(callback, { close_on_select = true })
end

function M.select_scheme(callback)
	defer_print("Loading schemes...")
	pickers.select_scheme(callback, { close_on_select = true })
end

function M.select_testplan(callback)
	defer_print("Loading test plans...")
	pickers.select_testplan(callback, { close_on_select = true })
end

function M.select_device(callback)
	defer_print("Loading devices...")
	pickers.select_destination(callback, { close_on_select = true })
end

return M
