local ui = require("xcodebuild.ui")
local coordinator = require("xcodebuild.coordinator")
local autocmd = require("xcodebuild.autocmd")

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

	vim.api.nvim_set_keymap("n", "dx", "", {
		callback = function()
			ui.toggle_logs()
		end,
	})
end

return M
