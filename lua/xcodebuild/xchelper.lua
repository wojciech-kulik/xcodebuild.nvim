local M = {}

local util = require("xcodebuild.util")

function M.get_booted_device_id()
	local output = util.shell("xcrun simctl list | grep Booted")
	return string.match(output, ".* %(([%w%-]*)%) %(Booted%)")
end

function M.get_project_scheme()
	local workspace = vim.fn.getcwd()
	local buildJsonContent = vim.fn.readfile(workspace .. "/buildServer.json")
	local buildJson = vim.fn.json_decode(buildJsonContent)
	return buildJson["scheme"]
end

return M
