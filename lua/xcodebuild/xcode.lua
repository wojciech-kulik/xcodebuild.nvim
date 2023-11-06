local util = require("xcodebuild.util")

local M = {}

function M.get_targets_list(appPath)
	if not appPath then
		vim.print("Could not locate build dir. Please run Build.")
		return {}
	end

	local searchPath = string.match(appPath, "(.*/Build)/Products")
	if not searchPath then
		vim.print("Could not locate build dir. Please run Build.")
		return {}
	end

	searchPath = searchPath .. "/Intermediates.noindex"

	local targetToFiles = {}
	local fileListFiles = util.shell("find '" .. searchPath .. "' -type f -iname *.SwiftFileList")

	for _, file in ipairs(fileListFiles) do
		if file ~= "" then
			local target = util.get_filename(file)
			local success, content = pcall(vim.fn.readfile, file)

			if success then
				targetToFiles[target] = targetToFiles[target] or {}

				for _, line in ipairs(content) do
					table.insert(targetToFiles[target], line)
				end
			end
		end
	end

	return targetToFiles
end

function M.get_runtimes(callback)
	local command = "xcrun simctl list runtimes -j -e"

	return vim.fn.jobstart(command, {
		stdout_buffered = true,
		on_stdout = function(_, output)
			local result = {}
			local json = vim.fn.json_decode(output)

			for _, runtime in ipairs(json.runtimes) do
				if runtime.isAvailable then
					local runtimeName = runtime.name .. " [" .. runtime.buildversion .. "]"
					table.insert(result, { name = runtimeName, id = runtime.identifier })
				end
			end

			callback(result)
		end,
	})
end

function M.get_devices(runtimeId, callback)
	local command = "xcrun simctl list devices -j -e"

	return vim.fn.jobstart(command, {
		stdout_buffered = true,
		on_stdout = function(_, output)
			local result = {}
			local json = vim.fn.json_decode(output)

			for _, device in ipairs(json.devices[runtimeId]) do
				local deviceName = device.name .. " [" .. device.udid .. "]"
				deviceName = deviceName .. (device.state == "Booted" and " (Booted)" or "")
				table.insert(result, { name = deviceName, id = device.udid })
			end

			callback(result)
		end,
	})
end

function M.get_destinations(projectCommand, scheme, callback)
	local command = "xcodebuild -showdestinations " .. projectCommand .. " -scheme '" .. scheme .. "'"

	return vim.fn.jobstart(command, {
		stdout_buffered = true,
		on_stdout = function(_, output)
			local result = {}
			local foundDestinations = false

			for _, line in ipairs(output) do
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

			callback(result)
		end,
	})
end

function M.get_schemes(projectCommand, callback)
	local command = "xcodebuild " .. projectCommand .. " -list"

	return vim.fn.jobstart(command, {
		stdout_buffered = true,
		on_stdout = function(_, output)
			local result = {}

			local foundSchemes = false
			for _, line in ipairs(output) do
				if foundSchemes and util.trim(line) == "" then
					break
				elseif foundSchemes then
					table.insert(result, util.trim(line))
				elseif string.find(util.trim(line), "Schemes") then
					foundSchemes = true
				end
			end

			callback(result)
		end,
	})
end

function M.get_testplans(projectCommand, scheme, callback)
	local command = "xcodebuild test " .. projectCommand .. " -scheme '" .. scheme .. "' -showTestPlans"

	return vim.fn.jobstart(command, {
		stdout_buffered = true,
		on_stdout = function(_, output)
			local result = {}

			local foundTestPlans = false
			for _, line in ipairs(output) do
				if foundTestPlans and util.trim(line) == "" then
					break
				elseif foundTestPlans then
					table.insert(result, util.trim(line))
				elseif string.find(util.trim(line), "Test plans") then
					foundTestPlans = true
				end
			end

			callback(result)
		end,
	})
end

function M.build_project(opts)
	local action = opts.build_for_testing and "build-for-testing " or ""
	local command = "xcodebuild "
		.. action
		.. opts.projectCommand
		.. " -scheme '"
		.. opts.scheme
		.. "' -destination 'id="
		.. opts.destination
		.. "'"

	return vim.fn.jobstart(command, {
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

	return vim.fn.jobstart(command, {
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

	for i = #logs, 1, -1 do
		local line = logs[i]
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

	return vim.fn.jobstart(command, {
		stdout_buffered = true,
		on_exit = function(_, code, _)
			if code ~= 0 then
				vim.notify("Could not install app (code: " .. code .. ")", vim.log.levels.ERROR)
			else
				callback()
			end
		end,
	})
end

function M.launch_app(destination, bundleId, callback)
	local command = "xcrun simctl launch --terminate-running-process '" .. destination .. "' " .. bundleId
	return vim.fn.jobstart(command, {
		stdout_buffered = true,
		detach = true,
		on_exit = function(_, code, _)
			if code ~= 0 then
				vim.notify("Could not launch app (code: " .. code .. ")", vim.log.levels.ERROR)
			else
				callback()
			end
		end,
	})
end

function M.uninstall_app(destination, bundleId, callback)
	local command = "xcrun simctl uninstall '" .. destination .. "' " .. bundleId
	return vim.fn.jobstart(command, {
		stdout_buffered = true,
		on_exit = function(_, code, _)
			if code ~= 0 then
				vim.notify("Could not uninstall app (code: " .. code .. ")", vim.log.levels.ERROR)
			else
				callback()
			end
		end,
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

	if opts.testsToRun then
		for _, test in ipairs(opts.testsToRun) do
			command = command .. " -only-testing " .. test
		end
	end

	vim.cmd("silent wa!")
	return vim.fn.jobstart(command, {
		stdout_buffered = false,
		stderr_buffered = false,
		on_stdout = opts.on_stdout,
		on_stderr = opts.on_stderr,
		on_exit = opts.on_exit,
	})
end

function M.list_tests(opts, callback)
	local command = "xcodebuild test -scheme '"
		.. opts.scheme
		.. "' -destination 'id="
		.. opts.destination
		.. "' "
		.. opts.projectCommand
		.. " -testPlan '"
		.. opts.testPlan
		.. "' -enumerate-tests"
		.. " -test-enumeration-style flat"

	local tests = {}
	local foundTests = false

	vim.cmd("silent wa!")
	return vim.fn.jobstart(command, {
		stdout_buffered = false,
		on_stdout = function(_, output)
			for _, line in ipairs(output) do
				if foundTests then
					local target, class, test = string.match(line, "%s*([^/]*)/([^/]*)/(test[^/]*)%s*")
					if target and class and test then
						table.insert(tests, {
							target = target,
							class = class,
							name = test,
							classId = target .. "/" .. class,
							testId = target .. "/" .. class .. "/" .. test,
						})
					end
				elseif string.find(line, "Plan " .. opts.testPlan) then
					foundTests = true
				end
			end
		end,
		on_exit = function(_, code, _)
			if code == 143 then
				return
			end
			callback(tests)
		end,
	})
end

return M
