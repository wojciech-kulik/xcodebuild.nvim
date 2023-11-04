local coordinator = require("xcodebuild.coordinator")

local M = {}

function M.build_and_install(callback)
	coordinator.build_and_install_app(function()
		callback()
	end)
end

return M
