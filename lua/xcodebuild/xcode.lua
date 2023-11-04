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

function M.build_project(opts)
	local command = "xcodebuild "
		.. opts.projectCommand
		.. " -scheme '"
		.. opts.scheme
		.. "' -destination 'id="
		.. opts.destination
		.. "'"

	vim.fn.jobstart(command, {
		stdout_buffered = false,
		stderr_buffered = false,
		on_stdout = opts.on_stdout,
		on_stderr = opts.on_stderr,
		on_exit = opts.on_exit,
	})
end

function M.get_bundle_id(projectCommand, scheme, callback)
	local command = "xcodebuild "
		.. projectCommand
		.. " -scheme '"
		.. scheme
		.. "' -showBuildSettings | grep PRODUCT_BUNDLE_IDENTIFIER | awk -F ' = ' '{print $2}'"

	vim.fn.jobstart(command, {
		stdout_buffered = true,
		on_stdout = function(_, output)
			callback(true, table.concat(output, ""))
		end,
	})
end

function M.get_app_settings(logs)
	local targetName = nil
	local buildDir = nil
	local bundleId = nil

	for _, line in ipairs(logs) do
		if string.find(line, "TARGETNAME") then
			targetName = string.match(line, "TARGETNAME\\=(.*)")
		elseif string.find(line, "TARGET_BUILD_DIR") then
			buildDir = string.match(line, "TARGET_BUILD_DIR\\=(.*)")
		elseif string.find(line, "PRODUCT_BUNDLE_IDENTIFIER") then
			bundleId = string.match(line, "PRODUCT_BUNDLE_IDENTIFIER\\=(.*)")
		end

		if targetName and buildDir and bundleId then
			break
		end
	end

	if not targetName or not buildDir or not bundleId then
		error("Could not locate built app path")
	end

	targetName = string.gsub(targetName, "\\", "")
	buildDir = string.gsub(buildDir, "\\", "")

	local result = {
		appPath = buildDir .. "/" .. targetName .. ".app",
		targetName = targetName,
		bundleId = bundleId,
	}

	return result
end

function M.install_app(destination, appPath, callback)
	local command = "xcrun simctl install '" .. destination .. "' '" .. appPath .. "'"

	vim.fn.jobstart(command, {
		stdout_buffered = true,
		on_stdout = callback,
	})
end

function M.launch_app(destination, bundleId, callback)
	local command = "xcrun simctl launch --terminate-running-process '" .. destination .. "' " .. bundleId
	vim.fn.jobstart(command, {
		stdout_buffered = true,
		detach = true,
		on_exit = callback,
	})
end

function M.get_app_pid(target)
	local pid = util.shell("ps aux | grep '" .. target .. ".app' | grep -v grep | awk '{ print$2 }'")
	local pidString = pid and table.concat(pid, "") or nil

	return tonumber(pidString)
end

function M.kill_app(target)
	local pid = M.get_app_pid(target)

	if pid then
		util.shell("kill -9 " .. pid)
	end
end

function M.run_tests(opts)
	local command = "xcodebuild test -scheme '"
		.. opts.scheme
		.. "' -destination 'id="
		.. opts.destination
		.. "' "
		.. opts.projectCommand
		.. " -testPlan '"
		.. opts.testPlan
		.. "'"

	vim.cmd("silent wa!")
	vim.fn.jobstart(command, {
		stdout_buffered = false,
		stderr_buffered = false,
		on_stdout = opts.on_stdout,
		on_stderr = opts.on_stderr,
		on_exit = opts.on_exit,
	})
end

return M
