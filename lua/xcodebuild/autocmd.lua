local appdata = require("xcodebuild.appdata")
local coordinator = require("xcodebuild.coordinator")

local M = {}
local autogroup = vim.api.nvim_create_augroup("xcodebuild.nvim", { clear = true })

function M.setup()
	vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
		group = autogroup,
		pattern = "*" .. appdata.get_build_logs_filename(),
		callback = function(ev)
			coordinator.setup_log_buffer(ev.buf)
		end,
	})

	vim.api.nvim_create_autocmd({ "VimEnter" }, {
		group = autogroup,
		pattern = "*",
		once = true,
		callback = function()
			coordinator.load_last_report()
		end,
	})

	vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
		group = autogroup,
		pattern = "*Tests.swift",
		callback = function(ev)
			coordinator.refresh_buf_diagnostics(ev.buf, ev.file)
		end,
	})
end

return M
