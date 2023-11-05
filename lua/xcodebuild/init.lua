local coordinator = require("xcodebuild.coordinator")
local autocmd = require("xcodebuild.autocmd")
local logs = require("xcodebuild.logs")

local M = {}

function M.setup()
	autocmd.setup()

	vim.api.nvim_create_user_command("XcodebuildSetup", function()
		coordinator.configure_project()
	end, { nargs = 0 })

	vim.api.nvim_create_user_command("Build", function()
		coordinator.build_project({
			open_logs_on_success = true,
		}, function() end)
	end, { nargs = 0 })

	vim.api.nvim_create_user_command("Test", function()
		coordinator.run_tests()
	end, { nargs = 0 })

	vim.api.nvim_create_user_command("TestClass", function()
		coordinator.run_selected_tests({
			currentClass = true,
		})
	end, { nargs = 0 })

	vim.api.nvim_create_user_command("TestFunc", function()
		coordinator.run_selected_tests({
			currentTest = true,
		})
	end, { nargs = 0 })

	vim.api.nvim_create_user_command("TestSelected", function()
		coordinator.run_selected_tests({
			selectedTests = true,
		})
	end, { nargs = 0 })

	vim.api.nvim_create_user_command("TestFailing", function()
		coordinator.run_selected_tests({
			failingTests = true,
		})
	end, { nargs = 0 })

	vim.api.nvim_create_user_command("XcodebuildCancel", function()
		coordinator.cancel()
	end, { nargs = 0 })

	vim.api.nvim_set_keymap("n", "dx", "", {
		callback = function()
			logs.toggle_logs()
		end,
	})
end

return M
