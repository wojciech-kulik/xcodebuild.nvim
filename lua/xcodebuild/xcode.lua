local util = require("xcodebuild.util")
local parser = require("xcodebuild.parser")
local ui = require("xcodebuild.ui")

local M = {}

function M.get_runtimes()
	local result = {}
	local content = util.shell("xcrun simctl list runtimes -j -e")
	local json = vim.fn.json_decode(content)

	for _, runtime in ipairs(json.runtimes) do
		if runtime.isAvailable then
			local runtimeName = runtime.name .. " [" .. runtime.buildversion .. "]"
			table.insert(result, { name = runtimeName, id = runtime.identifier })
		end
	end

	return result
end

function M.get_devices(runtimeId)
	local result = {}
	local content = util.shell("xcrun simctl list devices -j -e")
	local json = vim.fn.json_decode(content)

	for _, device in ipairs(json.devices[runtimeId]) do
		local deviceName = device.name .. " [" .. device.udid .. "]"
		deviceName = deviceName .. (device.state == "Booted" and " (Booted)" or "")
		table.insert(result, { name = deviceName, id = device.udid })
	end

	return result
end

function M.get_destinations(projectCommand, scheme)
	local result = {}
	local content = util.shell("xcodebuild -showdestinations " .. projectCommand .. " -scheme '" .. scheme .. "'")

	local foundDestinations = false
	for _, line in ipairs(content) do
		if foundDestinations and util.trim(line) == "" then
			break
		elseif foundDestinations then
			local trimmed = string.gsub(util.trim(line), ", ", "@")
			local valuePattern = "%:%s*([^@}]-)%s*[@}]"
			local destination = {
				platform = string.match(trimmed, "platform" .. valuePattern),
				variant = string.match(trimmed, "variant" .. valuePattern),
				arch = string.match(trimmed, "arch" .. valuePattern),
				id = string.match(trimmed, "id" .. valuePattern),
				name = string.match(trimmed, "name" .. valuePattern),
				os = string.match(trimmed, "OS" .. valuePattern),
				error = string.match(trimmed, "error" .. valuePattern),
			}
			table.insert(result, destination)
		elseif string.find(util.trim(line), "Available destinations") then
			foundDestinations = true
		end
	end

	return result
end

function M.get_schemes(projectCommand)
	local result = {}
	local content = util.shell("xcodebuild " .. projectCommand .. " -list")

	local foundSchemes = false
	for _, line in ipairs(content) do
		if foundSchemes and util.trim(line) == "" then
			break
		elseif foundSchemes then
			table.insert(result, util.trim(line))
		elseif string.find(util.trim(line), "Schemes") then
			foundSchemes = true
		end
	end

	return result
end

function M.get_testplans(projectCommand, scheme)
	local result = {}
	local content = util.shell("xcodebuild test " .. projectCommand .. " -scheme '" .. scheme .. "' -showTestPlans")

	local foundTestPlans = false
	for _, line in ipairs(content) do
		if foundTestPlans and util.trim(line) == "" then
			break
		elseif foundTestPlans then
			table.insert(result, util.trim(line))
		elseif string.find(util.trim(line), "Test plans") then
			foundTestPlans = true
		end
	end

	return result
end

function M.build_project(projectCommand, scheme, destination, callback)
	local command = "xcodebuild "
		.. projectCommand
		.. " -scheme '"
		.. scheme
		.. "' -destination 'id="
		.. destination
		.. "'"

	local isFirstChunk = true
	local report = {}

	vim.print("Building...")
	vim.cmd("silent wa!")
	vim.fn.jobstart(command, {
		stdout_buffered = false,
		stderr_buffered = false,
		on_stdout = function(_, output)
			if isFirstChunk then
				parser.clear()
			end
			report = parser.parse_logs(output)
			isFirstChunk = false

			if report.buildErrors and report.buildErrors[1] then
				vim.cmd("echo 'Building... [Errors: " .. #report.buildErrors .. "]'")
			end
		end,
		on_stderr = function(_, output)
			if isFirstChunk then
				parser.clear()
				isFirstChunk = false
			end
			report = parser.parse_logs(output)
		end,
		on_exit = function()
			ui.show_logs(report)
			if not report.buildErrors or not report.buildErrors[1] then
				vim.print("BUILD SUCCEEDED")
			end
			ui.set_build_quickfix(report)
			callback()
		end,
	})
end

return M
