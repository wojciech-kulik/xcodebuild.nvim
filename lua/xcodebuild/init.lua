local autocmd = require("xcodebuild.autocmd")
local logs = require("xcodebuild.logs")
local actions = require("xcodebuild.actions")
local config = require("xcodebuild.config")

local M = {}

local function call(action)
	return function()
		action()
	end
end

function M.setup()
	autocmd.setup()
	config.load_settings()

	-- Build & Test
	vim.api.nvim_create_user_command("XcodebuildBuild", call(actions.build), { nargs = 0 })
	vim.api.nvim_create_user_command("XcodebuildRun", call(actions.run), { nargs = 0 })
	vim.api.nvim_create_user_command("XcodebuildCancel", call(actions.cancel), { nargs = 0 })
	vim.api.nvim_create_user_command("XcodebuildTest", call(actions.run_tests), { nargs = 0 })
	vim.api.nvim_create_user_command("XcodebuildTestClass", call(actions.run_class_tests), { nargs = 0 })
	vim.api.nvim_create_user_command("XcodebuildTestFunc", call(actions.run_func_test), { nargs = 0 })
	vim.api.nvim_create_user_command("XcodebuildTestSelected", call(actions.run_selected_tests), { nargs = 0 })
	vim.api.nvim_create_user_command("XcodebuildTestFailing", call(actions.run_failing_tests), { nargs = 0 })

	-- Pickers
	vim.api.nvim_create_user_command("XcodebuildPicker", call(actions.show_picker), { nargs = 0 })
	vim.api.nvim_create_user_command("XcodebuildSetup", call(actions.configure_project), { nargs = 0 })
	vim.api.nvim_create_user_command("XcodebuildSelectProject", call(actions.select_project), { nargs = 0 })
	vim.api.nvim_create_user_command("XcodebuildSelectScheme", call(actions.select_scheme), { nargs = 0 })
	vim.api.nvim_create_user_command("XcodebuildSelectDevice", call(actions.select_device), { nargs = 0 })
	vim.api.nvim_create_user_command("XcodebuildSelectTestPlan", call(actions.select_testplan), { nargs = 0 })

	-- Logs
	vim.api.nvim_create_user_command("XcodebuildToggleLogs", call(actions.toggle_logs), { nargs = 0 })
	vim.api.nvim_create_user_command("XcodebuildShowLogs", call(actions.show_logs), { nargs = 0 })
	vim.api.nvim_create_user_command("XcodebuildCloseLogs", call(actions.close_logs), { nargs = 0 })

	-- Other
	vim.api.nvim_create_user_command("XcodebuildUninstall", call(actions.uninstall), { nargs = 0 })

	-- Keymaps
	vim.api.nvim_set_keymap("n", "dx", "", {
		callback = function()
			logs.toggle_logs()
		end,
	})
end

return M
