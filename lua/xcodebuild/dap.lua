local util = require("xcodebuild.util")
local projectConfig = require("xcodebuild.project_config")
local xcode = require("xcodebuild.xcode")

local M = {}

function M.wait_for_pid()
	local co = coroutine
	local target = projectConfig.settings().appTarget

	if not target then
		error("You must build the application first")
	end

	return co.create(function(dap_run_co)
		local pid = nil

		vim.notify("Attaching debugger...")
		for _ = 1, 10 do
			util.shell("sleep 1")
			pid = xcode.get_app_pid(target)

			if tonumber(pid) then
				break
			end
		end

		if not tonumber(pid) then
			vim.notify("Launching the application timed out", vim.log.levels.ERROR)
			co.close(dap_run_co)
		end

		co.resume(dap_run_co, pid)
	end)
end

return M
