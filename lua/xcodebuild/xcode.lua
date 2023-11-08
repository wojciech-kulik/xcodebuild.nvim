local util = require("xcodebuild.util")
local notifications = require("xcodebuild.notifications")

local M = {}

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

  local targetsFilesMap = {}
  local fileListFiles = util.shell("find '" .. searchPath .. "' -type f -iname *.SwiftFileList")

  for _, file in ipairs(fileListFiles) do
    if file ~= "" then
      local target = util.get_filename(file)
      local success, content = pcall(vim.fn.readfile, file)

      if success then
        targetsFilesMap[target] = targetsFilesMap[target] or {}

        for _, line in ipairs(content) do
          table.insert(targetsFilesMap[target], line)
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

function M.get_project_information(projectCommand, callback)
  if string.find(projectCommand, "-workspace") then
    projectCommand = string.gsub(projectCommand, "-workspace", "-project")
    projectCommand = string.gsub(projectCommand, "%.xcworkspace", ".xcodeproj")
  end
  local command = "xcodebuild " .. projectCommand .. " -list"

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
        if string.find(util.trim(line), "Schemes:") then
          mode = SCHEME
        elseif string.find(util.trim(line), "Build Configurations:") then
          mode = CONFIG
        elseif string.find(util.trim(line), "Targets:") then
          mode = TARGET
        elseif util.trim(line) ~= "" then
          if mode == SCHEME then
            table.insert(schemes, util.trim(line))
          elseif mode == CONFIG then
            table.insert(configs, util.trim(line))
          elseif mode == TARGET then
            table.insert(targets, util.trim(line))
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
  local action = opts.buildForTesting and "build-for-testing " or ""
  local command = "xcodebuild "
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

  return vim.fn.jobstart(command, {
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = opts.on_stdout,
    on_stderr = opts.on_stderr,
    on_exit = opts.on_exit,
  })
end

function M.get_build_settings(platform, projectCommand, scheme, config, callback)
  local command = "xcodebuild "
    .. projectCommand
    .. " -scheme '"
    .. scheme
    .. "' -configuration '"
    .. config
    .. "' -showBuildSettings"
    .. " -sdk "
    .. (platform == "macOS" and "macosx" or "iphonesimulator")

  return vim.fn.jobstart(command, {
    stdout_buffered = true,
    on_stdout = function(_, output)
      local foundBundleId = nil
      local foundProductName = nil
      local foundBuildDir = nil

      for _, line in ipairs(output) do
        local bundleId = string.match(line, "PRODUCT_BUNDLE_IDENTIFIER = (.*)%s*")
        local productName = string.match(line, "PRODUCT_NAME = (.*)%s*")
        local buildDir = string.match(line, "TARGET_BUILD_DIR = (.*)%s*")
        if bundleId then
          foundBundleId = bundleId
        end
        if productName then
          foundProductName = productName
        end
        if buildDir then
          foundBuildDir = buildDir
        end
        if foundBuildDir and foundProductName and foundBundleId then
          break
        end
      end

      if not foundBundleId or not foundBuildDir or not foundProductName then
        error("Could not get build settings")
      end

      local result = {
        appPath = foundBuildDir .. "/" .. foundProductName .. ".app",
        productName = foundProductName,
        bundleId = foundBundleId,
      }

      if callback then
        callback(result)
      end
    end,
  })
end

function M.install_app(destination, appPath, callback)
  local command = "xcrun simctl install '" .. destination .. "' '" .. appPath .. "'"

  return vim.fn.jobstart(command, {
    stdout_buffered = true,
    on_exit = function(_, code, _)
      if code ~= 0 then
        notifications.send_error("Could not install app (code: " .. code .. ")")
        if code == 149 then
          notifications.send_warning("Make sure that the simulator is booted.")
        end
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
        notifications.send_error("Could not launch app (code: " .. code .. ")")
        if code == 149 then
          notifications.send_warning("Make sure that the simulator is booted.")
        end
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
        notifications.send_error("Could not uninstall app (code: " .. code .. ")")
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
    .. " -configuration '"
    .. opts.config
    .. "'"

  if opts.testsToRun then
    for _, test in ipairs(opts.testsToRun) do
      command = command .. " -only-testing " .. test
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
