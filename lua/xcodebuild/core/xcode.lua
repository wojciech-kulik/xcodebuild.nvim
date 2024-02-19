local util = require("xcodebuild.util")
local notifications = require("xcodebuild.broadcasting.notifications")

local M = {}
local CANCELLED_CODE = 143

local function show_stderr_output(_, output)
  if output and (#output > 1 or output[1] ~= "") then
    notifications.send_error(table.concat(output, "\n"))
  end
end

local function callback_or_error(action, callback)
  return function(_, code, _)
    if code ~= 0 then
      notifications.send_error("Could not " .. action .. " app (code: " .. code .. ")")
    else
      util.call(callback)
    end
  end
end

local function get_coverage_item_id(xcresultPath, callback)
  local command = "xcrun xcresulttool get --format json --path '" .. xcresultPath .. "'"

  return vim.fn.jobstart(command, {
    stdout_buffered = true,
    on_stdout = function(_, output)
      local result = vim.fn.json_decode(output)
      local _, coverageId = pcall(function()
        local coverage = result["actions"]["_values"][1]["actionResult"]["coverage"]
        if not coverage["archiveRef"] then
          return nil
        end
        return coverage["archiveRef"]["id"]["_value"]
      end, nil)

      callback(coverageId)
    end,
    on_exit = function(_, code, _)
      if code ~= 0 then
        notifications.send_error("Could not export code coverage (code: " .. code .. ")")
      end
    end,
  })
end

function M.get_targets_filemap(appPath)
  if not appPath then
    notifications.send_error("Could not locate build dir. Please run Build.")
    return {}
  end

  local searchPath = string.match(appPath, "(.*/Build)/Products")
  if not searchPath then
    notifications.send_error("Could not locate build dir. Please run Build.")
    return {}
  end

  searchPath = searchPath .. "/Intermediates.noindex"

  if not util.dir_exists(searchPath) then
    return {}
  end

  local targetsFilesMap = {}
  local fileListFiles = util.shell("find '" .. searchPath .. "' -type f -iname *.SwiftFileList")

  for _, file in ipairs(fileListFiles) do
    if file ~= "" then
      local target = util.get_filename(file)
      local success, content = pcall(vim.fn.readfile, file)

      if success then
        targetsFilesMap[target] = targetsFilesMap[target] or {}

        for _, line in ipairs(content) do
          local sanitizedLine = string.gsub(line, "%\\", "")
          table.insert(targetsFilesMap[target], sanitizedLine)
        end
      end
    end
  end

  return targetsFilesMap
end

function M.get_destinations(projectCommand, scheme, callback)
  local command = "xcodebuild -showdestinations " .. projectCommand .. " -scheme '" .. scheme .. "'"

  return vim.fn.jobstart(command, {
    stdout_buffered = true,
    on_stdout = function(_, output)
      local result = {}
      local foundDestinations = false
      local valuePattern = "%:%s*([^@}]-)%s*[@}]"

      for _, line in ipairs(output) do
        local trimmedLine = util.trim(line)

        if foundDestinations and trimmedLine == "" then
          break
        elseif foundDestinations then
          local sanitizedLine = string.gsub(trimmedLine, ", ", "@")
          local destination = {
            platform = string.match(sanitizedLine, "platform" .. valuePattern),
            variant = string.match(sanitizedLine, "variant" .. valuePattern),
            arch = string.match(sanitizedLine, "arch" .. valuePattern),
            id = string.match(sanitizedLine, "id" .. valuePattern),
            name = string.match(sanitizedLine, "name" .. valuePattern),
            os = string.match(sanitizedLine, "OS" .. valuePattern),
            error = string.match(sanitizedLine, "error" .. valuePattern),
          }
          table.insert(result, destination)
        elseif string.find(trimmedLine, "Available destinations") then
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
        local trimmedLine = util.trim(line)

        if foundSchemes and trimmedLine == "" then
          break
        elseif foundSchemes then
          table.insert(result, trimmedLine)
        elseif string.find(trimmedLine, "Schemes") then
          foundSchemes = true
        end
      end

      callback(result)
    end,
  })
end

function M.get_project_information(xcodeproj, callback)
  local command = "xcodebuild -project '" .. xcodeproj .. "' -list"

  return vim.fn.jobstart(command, {
    stdout_buffered = true,
    on_stdout = function(_, output)
      local schemes = {}
      local configs = {}
      local targets = {}
      local SCHEME = "scheme"
      local CONFIG = "config"
      local TARGET = "target"

      local mode = nil
      for _, line in ipairs(output) do
        local trimmedLine = util.trim(line)

        if string.find(trimmedLine, "Schemes:") then
          mode = SCHEME
        elseif string.find(trimmedLine, "Build Configurations:") then
          mode = CONFIG
        elseif string.find(trimmedLine, "Targets:") then
          mode = TARGET
        elseif trimmedLine ~= "" then
          if mode == SCHEME then
            table.insert(schemes, trimmedLine)
          elseif mode == CONFIG then
            table.insert(configs, trimmedLine)
          elseif mode == TARGET then
            table.insert(targets, trimmedLine)
          end
        else
          mode = nil
        end
      end

      callback({
        configs = configs,
        targets = targets,
        schemes = schemes,
      })
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
        local trimmedLine = util.trim(line)

        if foundTestPlans and trimmedLine == "" then
          break
        elseif foundTestPlans then
          table.insert(result, trimmedLine)
        elseif string.find(trimmedLine, "Test plans") then
          foundTestPlans = true
        end
      end

      callback(result)
    end,
  })
end

function M.build_project(opts)
  -- stylua: ignore
  local action = opts.buildForTesting and "build-for-testing " or "build "
  local command = "xcodebuild "
    .. (opts.clean and "clean " or "")
    .. action
    .. opts.projectCommand
    .. " -scheme '"
    .. opts.scheme
    .. "' -destination 'id="
    .. opts.destination
    .. "'"
    .. " -configuration '"
    .. opts.config
    .. "'"
    .. (string.len(opts.extraBuildArgs) > 0 and " " .. opts.extraBuildArgs or "")

  return vim.fn.jobstart(command, {
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = opts.on_stdout,
    on_stderr = opts.on_stderr,
    on_exit = opts.on_exit,
  })
end

function M.get_build_settings(platform, projectCommand, scheme, config, callback)
  local sdk = "iphonesimulator"
  if platform == "macOS" then
    sdk = "macosx"
  elseif platform == "iOS" then
    sdk = "iphoneos"
  end

  local command = "xcodebuild "
    .. projectCommand
    .. " -scheme '"
    .. scheme
    .. "' -configuration '"
    .. config
    .. "' -showBuildSettings"
    .. " -sdk "
    .. sdk

  local find_setting = function(source, key)
    return string.match(source, "%s+" .. key .. " = (.*)%s*")
  end

  return vim.fn.jobstart(command, {
    stdout_buffered = true,
    on_stdout = function(_, output)
      local bundleId = nil
      local productName = nil
      local wrapperName = nil
      local buildDir = nil

      for _, line in ipairs(output) do
        bundleId = bundleId or find_setting(line, "PRODUCT_BUNDLE_IDENTIFIER")
        productName = productName or find_setting(line, "PRODUCT_NAME")
        wrapperName = wrapperName or find_setting(line, "WRAPPER_NAME")
        buildDir = buildDir or find_setting(line, "TARGET_BUILD_DIR")

        if bundleId and productName and buildDir and wrapperName then
          break
        end
      end

      if not bundleId or (not productName and not wrapperName) or not buildDir then
        notifications.send_error("Could not get build settings")
        return
      end

      if wrapperName then
        wrapperName = wrapperName:gsub("%.app$", "")

        if vim.trim(wrapperName) ~= "" then
          productName = wrapperName
        end
      end

      local result = {
        appPath = buildDir .. "/" .. productName .. ".app",
        productName = productName,
        bundleId = bundleId,
      }

      util.call(callback, result)
    end,
  })
end

function M.install_app(platform, destination, appPath, callback)
  if platform == "iOS" then
    return M.install_app_on_device(destination, appPath, callback)
  else
    return M.install_app_on_simulator(destination, appPath, callback)
  end
end

function M.install_app_on_device(destination, appPath, callback)
  local appdata = require("xcodebuild.project.appdata")
  appdata.clear_app_logs()

  local command = "xcrun devicectl device install app -d '" .. destination .. "' '" .. appPath .. "'"

  return vim.fn.jobstart(command, {
    stderr_buffered = true,
    on_stderr = show_stderr_output,
    on_exit = callback_or_error("installl", callback),
  })
end

function M.install_app_on_simulator(destination, appPath, callback)
  local command = "xcrun simctl install '" .. destination .. "' '" .. appPath .. "'"

  return vim.fn.jobstart(command, {
    stdout_buffered = true,
    on_exit = function(_, code, _)
      if code ~= 0 then
        notifications.send_error("Could not install app (code: " .. code .. ")")
        if code == 149 then
          notifications.send_warning("Make sure that the simulator is booted")
        end
      else
        callback()
      end
    end,
  })
end

function M.launch_app_on_device(destination, bundleId, callback)
  local command = "xcrun devicectl device process launch --terminate-existing -d '"
    .. destination
    .. "' "
    .. bundleId

  return vim.fn.jobstart(command, {
    stderr_buffered = true,
    on_stderr = show_stderr_output,
    on_exit = callback_or_error("launch", callback),
  })
end

function M.launch_app_on_simulator(destination, bundleId, waitForDebugger, callback)
  local command = "xcrun simctl launch --terminate-running-process --console-pty"
    .. (waitForDebugger and " --wait-for-debugger" or "")
    .. " '"
    .. destination
    .. "' "
    .. bundleId

  local appdata = require("xcodebuild.project.appdata")

  local write_logs = function(_, output)
    if output[#output] == "" then
      table.remove(output, #output)
    end
    appdata.append_app_logs(output)
  end

  appdata.clear_app_logs()

  util.call(callback)

  return vim.fn.jobstart(command, {
    stdout_buffered = false,
    stderr_buffered = false,
    detach = true,
    on_stdout = write_logs,
    on_stderr = write_logs,
    on_exit = function(_, code, _)
      if code ~= 0 then
        notifications.send_error("Could not launch app (code: " .. code .. ")")
        if code == 149 then
          notifications.send_warning("Make sure that the simulator is booted")
        end
      end
    end,
  })
end

function M.launch_app(platform, destination, bundleId, waitForDebugger, callback)
  if platform == "iOS" then
    M.launch_app_on_device(destination, bundleId, callback)
  else
    M.launch_app_on_simulator(destination, bundleId, waitForDebugger, callback)
  end
end

function M.boot_simulator(destination, callback)
  local command = "xcrun simctl boot '" .. destination .. "' "

  return vim.fn.jobstart(command, {
    stdout_buffered = true,
    on_exit = function(_, code, _)
      if code ~= 0 then
        notifications.send_error("Could not boot simulator (code: " .. code .. ")")
      else
        local output = util.shell("xcode-select -p")
        if util.is_not_empty(output) then
          vim.fn.jobstart(output[1] .. "/Applications/Simulator.app/Contents/MacOS/Simulator", {
            detach = true,
            on_exit = function() end,
          })
        end

        callback()
      end
    end,
  })
end

function M.uninstall_app_from_simulator(destination, bundleId, callback)
  local command = "xcrun simctl uninstall '" .. destination .. "' " .. bundleId

  return vim.fn.jobstart(command, {
    stdout_buffered = true,
    on_exit = callback_or_error("uninstalll", callback),
  })
end

function M.uninstall_app_from_device(destination, bundleId, callback)
  local command = "xcrun devicectl device uninstall app -d  '" .. destination .. "' " .. bundleId

  return vim.fn.jobstart(command, {
    stderr_buffered = true,
    on_stderr = show_stderr_output,
    on_exit = callback_or_error("uninstalll", callback),
  })
end

function M.uninstall_app(platform, destination, bundleId, callback)
  if platform == "iOS" then
    return M.uninstall_app_from_device(destination, bundleId, callback)
  else
    return M.uninstall_app_from_simulator(destination, bundleId, callback)
  end
end

function M.get_app_pid(productName)
  local pid = util.shell("ps aux | grep '" .. productName .. ".app' | grep -v grep | awk '{ print$2 }'")

  return tonumber(pid and pid[1] or nil)
end

function M.kill_app(productName, callback)
  -- TODO: kill on device with iOS 17
  local pid = M.get_app_pid(productName)

  if pid then
    util.shell("kill -9 " .. pid)
  end

  util.call(callback)
end

function M.get_code_coverage(archive, filepath, callback)
  local command = "xcrun xccov view --file '" .. filepath .. "' '" .. archive .. "'"

  return vim.fn.jobstart(command, {
    stdout_buffered = true,
    on_stdout = function(_, output)
      callback(output)
    end,
    on_exit = function() end,
  })
end

function M.export_code_coverage(xcresultPath, outputPath, callback)
  return get_coverage_item_id(xcresultPath, function(itemId)
    if not itemId then
      notifications.send(
        "Could not export code coverage. Make sure that code coverage is enabled for your test plan"
      )
      util.call(callback)
      return
    end

    local command = "xcrun xcresulttool export --type directory"
      .. " --id "
      .. itemId
      .. " --path '"
      .. xcresultPath
      .. "' --output-path '"
      .. outputPath
      .. "'"

    vim.fn.jobstart(command, {
      stdout_buffered = true,
      on_exit = function(_, code, _)
        if code ~= 0 then
          notifications.send_error("Could not export code coverage (code: " .. code .. ")")
        end
        util.call(callback)
      end,
    })
  end)
end

function M.enumerate_tests(opts, callback)
  local appdata = require("xcodebuild.project.appdata")
  local outputPath = appdata.tests_filepath
  util.shell("rm -rf '" .. outputPath .. "'")

  local command = "xcodebuild test-without-building"
    .. " -enumerate-tests"
    .. " -scheme '"
    .. opts.scheme
    .. "' -destination 'id="
    .. opts.destination
    .. "' -configuration '"
    .. opts.config
    .. "' "
    .. opts.projectCommand
    .. " -testPlan '"
    .. opts.testPlan
    .. "' -test-enumeration-format json"
    .. " -test-enumeration-output-path '"
    .. outputPath
    .. "' -disableAutomaticPackageResolution -skipPackageUpdates -parallelizeTargets"
    .. " -test-enumeration-style flat"
    .. (string.len(opts.extraTestArgs) > 0 and " " .. opts.extraTestArgs or "")

  return vim.fn.jobstart(command, {
    on_exit = function(_, code, _)
      if code == CANCELLED_CODE then
        notifications.send_warning("Loading tests cancelled")
        return
      end

      if code ~= 0 then
        notifications.send_error("Could not list tests (code: " .. code .. ")")
        return
      end

      local tests = require("xcodebuild.tests.enumeration_parser").parse(outputPath)
      util.call(callback, tests)
    end,
  })
end

function M.export_code_coverage_report(xcresultPath, outputPath, callback)
  local command = "xcrun xccov view --report --json '" .. xcresultPath .. "' > '" .. outputPath .. "'"

  vim.fn.jobstart(command, {
    stdout_buffered = true,
    on_exit = function()
      util.call(callback)
    end,
  })
end

function M.run_tests(opts)
  local action = opts.withoutBuilding and "test-without-building" or "test"

  -- stylua: ignore
  local command = "xcodebuild " .. action .. " -scheme '"
    .. opts.scheme
    .. "' -destination 'id="
    .. opts.destination
    .. "' "
    .. opts.projectCommand
    .. " -testPlan '"
    .. opts.testPlan
    .. "'"
    .. " -configuration '"
    .. opts.config
    .. "'"
    .. (string.len(opts.extraTestArgs) > 0 and " " .. opts.extraTestArgs or "")

  if opts.testsToRun then
    for _, test in ipairs(opts.testsToRun) do
      command = command .. " -only-testing '" .. test .. "'"
    end
  end

  return vim.fn.jobstart(command, {
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = opts.on_stdout,
    on_stderr = opts.on_stderr,
    on_exit = opts.on_exit,
  })
end

return M
