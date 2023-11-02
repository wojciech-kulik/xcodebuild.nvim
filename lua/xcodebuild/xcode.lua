local util = require("xcodebuild.util")
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
	local content = util.shell("xcodebuild -showdestinations " .. projectCommand .. " -scheme " .. scheme)
	content = vim.split(content, "\n", { plain = true })

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
	content = vim.split(content, "\n", { plain = true })

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
	local content = util.shell("xcodebuild test " .. projectCommand .. " -scheme " .. scheme .. " -showTestPlans")
	content = vim.split(content, "\n", { plain = true })

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

return M
