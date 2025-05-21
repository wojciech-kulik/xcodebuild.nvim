---@mod xcodebuild.core.xcode Xcodebuild Wrapper
---@brief [[
---This module contains the wrapper for the `xcodebuild` tool.
---
---It is used to interact with the Xcode project and perform various actions.
---@brief ]]

---Hash map of targets to list of file paths.
---@alias TargetMap table<string, string[]>

---@class XcodeDevice
---@field platform string|nil
---@field variant string|nil
---@field arch string|nil
---@field id string|nil
---@field name string|nil
---@field os string|nil
---@field error string|nil

---@class XcodeProjectInfo
---@field configs string[]
---@field targets string[]
---@field schemes string[]

---@class XcodeBuildOptions
---@field workingDirectory string|nil
---@field buildForTesting boolean|nil
---@field clean boolean|nil
---@field projectFile string|nil
---@field scheme string
---@field destination string
---@field extraBuildArgs string[]
---@field on_stdout function
---@field on_stderr fun(_, output: string[], _)
---@field on_exit fun(_, code: number, _)

---@class XcodeTestOptions
---@field workingDirectory string|nil
---@field withoutBuilding boolean|nil
---@field projectFile string|nil
---@field scheme string
---@field destination string
---@field testPlan string|nil
---@field testsToRun string[]|nil
---@field extraTestArgs string[]
---@field on_stdout function
---@field on_stderr fun(_, output: string[], _)
---@field on_exit fun(_, code: number, _)

---@class XcodeEnumerateOptions
---@field workingDirectory string|nil
---@field projectFile string
---@field scheme string
---@field destination string
---@field testPlan string
---@field extraTestArgs string[]

---@class XcodeBuildSettings
---@field appPath string
---@field productName string
---@field bundleId string
---@field buildDir string|nil

---@class XcodeScheme
---@field name string
---@field filepath string|nil

local util = require("xcodebuild.util")
local notifications = require("xcodebuild.broadcasting.notifications")
local constants = require("xcodebuild.core.constants")
local xcodebuildOffline = require("xcodebuild.integrations.xcodebuild-offline")

local M = {}
local CANCELLED_CODE = 143
local DEBUG = false

---@diagnostic disable: unused-local
---Prints the message if the DEBUG flag is set to true.
---@param name string
---@param value any
local function debug_print(name, value)
  if DEBUG then
    print(name .. ":", vim.inspect(value))
  end
end

---Sends the stderr output as an error notification.
---@param _ number
---@param output string[]
local function show_stderr_output(_, output)
  if output and (#output > 1 or output[1] ~= "") then
    notifications.send_error(table.concat(output, "\n"))
  end
end

---Sends the callback or an error notification based on the exit code.
---@param action string
---@param callback function|nil
---@return fun(_, number, _)
local function callback_or_error(action, callback)
  return function(_, code, _)
    if code ~= 0 then
      notifications.send_error("Could not " .. action .. " app (code: " .. code .. ")")
    else
      util.call(callback)
    end
  end
end

---Returns `-project` or `-workspace` based on the project file extension.
---@param projectFile string|nil
---@return string|nil
local function get_project_param(projectFile)
  if not projectFile then
    return nil
  end

  return util.has_suffix(projectFile, "xcodeproj") and "-project" or "-workspace"
end

---Returns derived data path for Swift Package {productName} that matches the {workingDirectory}.
---@param productName string
---@param workingDirectory string
---@return string|nil
function M.find_derived_data_path(productName, workingDirectory)
  local derivedDataDir = vim.fn.expand("~/Library/Developer/Xcode/DerivedData")
  -- stylua: ignore
  local cmd = {
    "find",
    derivedDataDir,
    "-name",
    productName .. "-*",
    "-maxdepth", "1",
    "-type", "d",
  }

  if util.is_fd_installed() then
    -- stylua: ignore
    cmd = {
      "fd",
      "-I",
      productName .. "\\-.*",
      derivedDataDir,
      "--max-depth", "1",
      "--type", "d",
    }
  end

  local dirs = util.shell(cmd)

  for _, dir in ipairs(dirs) do
    if string.find(dir, productName) then
      local trimmedDir = dir:gsub("/+$", "")
      local workspacePath = util.shell({
        "/usr/libexec/PlistBuddy",
        "-c",
        "Print WorkspacePath",
        trimmedDir .. "/info.plist",
      })

      if workspacePath and workspacePath[1] == workingDirectory then
        return trimmedDir
      end
    end
  end

  return nil
end

---Returns a map of targets to list of file paths based on
---the `SwiftFileList` files in the build directory.
---
---If the build directory is not found, it returns an empty map.
---@param derivedDataPath string|nil
---@return TargetMap
function M.get_targets_filemap(derivedDataPath)
  if not derivedDataPath then
    notifications.send_error("Could not locate build dir. Please run Build.")
    return {}
  end

  local searchPath = string.match(derivedDataPath, "(.*/Build)/Products")
  if not searchPath then
    searchPath = derivedDataPath .. "/Build"
  end

  if not util.dir_exists(searchPath) then
    return {}
  end

  searchPath = searchPath .. "/Intermediates.noindex"

  if not util.dir_exists(searchPath) then
    return {}
  end

  local targetsFilesMap = {}
  local cmd = { "find", searchPath, "-type", "f", "-iname", "*.SwiftFileList" }

  if util.is_fd_installed() then
    cmd = { "fd", "-I", ".*\\.SwiftFileList$", searchPath, "--type", "f" }
  end

  local fileListFiles = util.shell(cmd)

  for _, file in ipairs(fileListFiles) do
    if file ~= "" then
      local target = util.get_filename(file)
      local success, content = util.readfile(file)

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

---Returns the list of devices which match project requirements.
---@param projectFile string|nil
---@param scheme string
---@param workingDirectory string|nil
---@param callback fun(destinations: XcodeDevice[])
---@return number # job id
function M.get_destinations(projectFile, scheme, workingDirectory, callback)
  local command = {
    "xcodebuild",
    get_project_param(projectFile),
    projectFile,
    "-showdestinations",
    "-scheme",
    scheme,
  }
  command = util.skip_nil(command)
  command = xcodebuildOffline.wrap_command_if_needed(command)
  debug_print("get_destinations", command)

  return vim.fn.jobstart(command, {
    stdout_buffered = true,
    cwd = workingDirectory,
    on_stdout = function(_, output)
      local result = {}
      local foundDestinations = false
      local valuePattern = ":%s*([^@}]-)%s*[@}]"

      for _, line in ipairs(output) do
        local trimmedLine = util.trim(line)

        if foundDestinations and trimmedLine == "" then
          break
        elseif foundDestinations and vim.startswith(trimmedLine, "{") then
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

          if destination.platform and destination.id and destination.name then
            table.insert(result, destination)
          end
        elseif string.find(trimmedLine, "Available destinations") then
          foundDestinations = true
        end
      end

      callback(result)
    end,
  })
end

---Returns the list of schemes for the given project.
---@param projectFile string|nil
---@param workingDirectory string|nil
---@param callback fun(schemes: string[])
---@return number # job id
function M.get_schemes(projectFile, workingDirectory, callback)
  local command = {
    "xcodebuild",
    get_project_param(projectFile),
    projectFile,
    "-list",
  }
  command = util.skip_nil(command)
  command = xcodebuildOffline.wrap_command_if_needed(command)
  debug_print("get_schemes", command)

  return vim.fn.jobstart(command, {
    stdout_buffered = true,
    cwd = workingDirectory,
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

---Returns the list of schemes for the given project.
---@param xcodeprojPath string|nil
---@param workingDirectory string|nil
---@param callback fun(schemes: XcodeScheme[])
---@return number|nil # job id
function M.find_schemes(xcodeprojPath, workingDirectory, callback)
  ---@type XcodeScheme[]
  local result = {}

  local function returnResult()
    table.sort(result, function(a, b)
      return a.name < b.name
    end)

    util.call(callback, result)
  end

  if xcodeprojPath then
    local schemes = util.shell({ "find", xcodeprojPath, "-name", "*.xcscheme", "-type", "f" })

    for _, scheme in ipairs(schemes) do
      local path = vim.trim(scheme)
      local filename = util.get_filename(path)
      if path and filename and path ~= "" and filename ~= "" then
        table.insert(result, { name = filename, filepath = path })
      end
    end
  end

  if #result == 0 then
    return M.get_project_information(xcodeprojPath, workingDirectory, function(settings)
      for _, scheme in ipairs(settings.schemes) do
        table.insert(result, { name = scheme })
      end

      returnResult()
    end)
  else
    returnResult()
  end
end

---Returns the list of project information including schemes, configs, and
---targets for the given {projectFile}.
---@param projectFile string|nil
---@param workingDirectory string|nil
---@param callback fun(settings: XcodeProjectInfo)
---@return number # job id
function M.get_project_information(projectFile, workingDirectory, callback)
  local command = { "xcodebuild", "-list" }

  if projectFile then
    command = {
      "xcodebuild",
      get_project_param(projectFile),
      projectFile,
      "-list",
    }
  end

  command = xcodebuildOffline.wrap_command_if_needed(command)
  debug_print("get_project_information", command)

  return vim.fn.jobstart(command, {
    stdout_buffered = true,
    cwd = workingDirectory,
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

---Returns the list of test plans for the given project.
---@param projectFile string
---@param scheme string
---@param callback fun(testPlans: string[])
---@return number # job id
function M.get_testplans(projectFile, scheme, callback)
  local command = {
    "xcodebuild",
    "test",
    get_project_param(projectFile),
    projectFile,
    "-scheme",
    scheme,
    "-showTestPlans",
  }
  command = util.skip_nil(command)
  command = xcodebuildOffline.wrap_command_if_needed(command)
  debug_print("get_testplans", command)

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

---Builds the project with the given options.
---@param opts XcodeBuildOptions
---@return number # job id
function M.build_project(opts)
  local appdata = require("xcodebuild.project.appdata")
  vim.fn.delete(appdata.build_xcresult_filepath, "rf")

  local command = {
    "xcodebuild",
    opts.clean and "clean" or nil,
    opts.buildForTesting and "build-for-testing" or "build",
    get_project_param(opts.projectFile),
    opts.projectFile,
    "-scheme",
    opts.scheme,
    "-destination",
    "id=" .. opts.destination,
    "-resultBundlePath",
    appdata.build_xcresult_filepath,
  }
  command = util.merge_array(command, opts.extraBuildArgs)
  command = util.skip_nil(command)
  command = xcodebuildOffline.wrap_command_if_needed(command)
  debug_print("build_project", command)

  return vim.fn.jobstart(command, {
    stdout_buffered = false,
    stderr_buffered = false,
    cwd = opts.workingDirectory,
    on_stdout = opts.on_stdout,
    on_stderr = opts.on_stderr,
    on_exit = opts.on_exit,
  })
end

---Returns the build settings for the given project.
---
---If one of the settings is not found, it will send an error notification.
---@param platform string
---@param projectFile string
---@param scheme string
---@param xcodeprojPath string
---@param callback fun(settings: XcodeBuildSettings)
---@return number|nil # job id
function M.get_build_settings(platform, projectFile, scheme, xcodeprojPath, callback)
  local sdk = constants.get_sdk(platform)

  local jobid
  jobid = M.find_schemes(xcodeprojPath, nil, function()
    local command = {
      "xcodebuild",
      "build",
      get_project_param(projectFile),
      projectFile,
      "-scheme",
      scheme,
      "-showBuildSettings",
      "-sdk",
      sdk,
    }
    command = util.skip_nil(command)
    command = xcodebuildOffline.wrap_command_if_needed(command)

    debug_print("get_build_settings", command)

    local find_setting = function(source, key)
      return string.match(source, "%s+" .. key .. " = (.*)%s*")
    end

    jobid = vim.fn.jobstart(command, {
      stdout_buffered = true,
      on_stdout = function(_, output)
        local bundleId = nil
        local productName = nil
        local wrapperName = nil
        local targetBuildDir = nil
        local buildDir = nil

        for _, line in ipairs(output) do
          bundleId = bundleId or find_setting(line, "PRODUCT_BUNDLE_IDENTIFIER")
          productName = productName or find_setting(line, "PRODUCT_NAME")
          wrapperName = wrapperName or find_setting(line, "WRAPPER_NAME")
          targetBuildDir = targetBuildDir or find_setting(line, "TARGET_BUILD_DIR")
          buildDir = buildDir or find_setting(line, "BUILD_DIR")

          if bundleId and productName and targetBuildDir and wrapperName and buildDir then
            break
          end
        end

        if (not productName and not wrapperName) or not targetBuildDir then
          notifications.send_error("Could not get build settings")
          return
        end

        --- Static library does not have a bundle id
        if not bundleId then
          notifications.send_warning("Could not find bundle id. Ignore if it's a static library.")
        end

        if wrapperName then
          wrapperName = wrapperName:gsub("%.app$", "")

          if vim.trim(wrapperName) ~= "" then
            productName = wrapperName
          end
        end

        local result = {
          appPath = targetBuildDir .. "/" .. productName .. ".app",
          productName = productName,
          bundleId = bundleId,
          buildDir = buildDir,
        }

        util.call(callback, result)
      end,
    })
  end)

  return jobid
end

---Installs the application on the given platform and destination.
---@param platform string
---@param destination string
---@param appPath string
---@param callback function|nil
---@return number # job id
function M.install_app(platform, destination, appPath, callback)
  if constants.is_simulator(platform) then
    return M.install_app_on_simulator(destination, appPath, true, callback)
  else
    return M.install_app_on_device(destination, appPath, callback)
  end
end

---Installs the application on device.
---@param destination string
---@param appPath string
---@param callback function|nil
---@return number # job id
function M.install_app_on_device(destination, appPath, callback)
  local appdata = require("xcodebuild.project.appdata")
  appdata.clear_app_logs()

  local command = { "xcrun", "devicectl", "device", "install", "app", "-d", destination, appPath }
  debug_print("install_app_on_device", command)

  return vim.fn.jobstart(command, {
    stderr_buffered = true,
    on_stderr = show_stderr_output,
    on_exit = callback_or_error("install", callback),
  })
end

---Installs the application on simulator.
---@param destination string
---@param appPath string
---@param bootIfNeeded boolean|nil
---@param callback function|nil
---@return number # job id
function M.install_app_on_simulator(destination, appPath, bootIfNeeded, callback)
  local command = { "xcrun", "simctl", "install", destination, appPath }
  debug_print("install_app_on_simulator", command)

  return vim.fn.jobstart(command, {
    stdout_buffered = true,
    on_exit = function(_, code, _)
      if code == 0 then
        util.call(callback)
      elseif code == 149 and bootIfNeeded then
        notifications.send("Booting the simulator...")

        M.boot_simulator(destination, function(success)
          if success then
            M.install_app_on_simulator(destination, appPath, false, callback)
          else
            notifications.send_warning("Make sure that the simulator is booted.")
          end
        end)
      elseif code == 149 then
        notifications.send_warning("Make sure that the simulator is booted.")
      else
        notifications.send_error("Could not install app (code: " .. code .. ")")
      end
    end,
  })
end

---Launches the application on device.
---@param destination string
---@param bundleId string
---@param callback function|nil
---@return number # job id
function M.launch_app_on_device(destination, bundleId, callback)
  local command = {
    "xcrun",
    "devicectl",
    "device",
    "process",
    "launch",
    "--terminate-existing",
    "-d",
    destination,
    bundleId,
  }

  local appdata = require("xcodebuild.project.appdata")
  local runArgs = appdata.read_run_args()
  if runArgs then
    table.insert(command, "--")
    for _, value in ipairs(runArgs) do
      table.insert(command, value)
    end
  end

  debug_print("launch_app_on_device", command)

  local env = nil
  for key, value in pairs(appdata.read_env_vars() or {}) do
    env = env or {}
    env["DEVICECTL_CHILD_" .. key] = value
  end

  return vim.fn.jobstart(command, {
    env = env,
    stderr_buffered = true,
    on_stderr = show_stderr_output,
    on_exit = callback_or_error("launch", callback),
  })
end

---Launches the application on simulator.
---It also streams logs to file and DAP console.
---@param destination string
---@param bundleId string
---@param waitForDebugger boolean
---@param callback function|nil
---@return number # job id
function M.launch_app_on_simulator(destination, bundleId, waitForDebugger, callback)
  local command = {
    "xcrun",
    "simctl",
    "launch",
    "--terminate-running-process",
    "--console-pty",
    waitForDebugger and "--wait-for-debugger" or nil,
    destination,
    bundleId,
  }
  command = util.skip_nil(command)

  local appdata = require("xcodebuild.project.appdata")
  local runArgs = appdata.read_run_args()
  if runArgs then
    table.insert(command, "--")
    for _, value in ipairs(runArgs) do
      table.insert(command, value)
    end
  end

  debug_print("launch_app_on_simulator", command)

  local env = nil
  for key, value in pairs(appdata.read_env_vars() or {}) do
    env = env or {}
    env["SIMCTL_CHILD_" .. key] = value
  end

  local write_logs = function(_, output)
    if output[#output] == "" then
      table.remove(output, #output)
    end
    appdata.append_app_logs(output)
  end

  appdata.clear_app_logs()

  util.call(callback)

  if require("xcodebuild.core.config").options.commands.focus_simulator_on_app_launch then
    util.shell("open -a Simulator")
  end

  return vim.fn.jobstart(command, {
    env = env,
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

---Launches the application on the given platform and destination.
---@param platform string
---@param destination string
---@param bundleId string
---@param waitForDebugger boolean
---@param callback function|nil
---@return number|nil # job id
function M.launch_app(platform, destination, bundleId, waitForDebugger, callback)
  if constants.is_simulator(platform) then
    return M.launch_app_on_simulator(destination, bundleId, waitForDebugger, callback)
  else
    return M.launch_app_on_device(destination, bundleId, callback)
  end
end

---Boots the simulator and launches the Simulator app if needed.
---@param destination string
---@param callback fun(success:boolean)|nil
---@return number # job id
function M.boot_simulator(destination, callback)
  local command = { "xcrun", "simctl", "boot", destination }
  debug_print("boot_simulator", command)

  return vim.fn.jobstart(command, {
    stdout_buffered = true,
    on_exit = function(_, code, _)
      if code == 0 then
        local output = util.shell("xcode-select -p")

        if util.is_not_empty(output) then
          vim.fn.jobstart(output[1] .. "/Applications/Simulator.app/Contents/MacOS/Simulator", {
            detach = true,
            on_exit = function() end,
          })
        end

        util.call(callback, true)
      else
        notifications.send_error("Could not boot simulator (code: " .. code .. ")")
        util.call(callback, false)
      end
    end,
  })
end

---Uninstalls the application from simulator.
---@param destination string
---@param bundleId string
---@param callback function|nil
---@return number # job id
function M.uninstall_app_from_simulator(destination, bundleId, callback)
  local command = { "xcrun", "simctl", "uninstall", destination, bundleId }
  debug_print("uninstall_app_from_simulator", command)

  return vim.fn.jobstart(command, {
    stdout_buffered = true,
    on_exit = callback_or_error("uninstall", callback),
  })
end

---Uninstalls the application from device.
---@param destination string
---@param bundleId string
---@param callback function|nil
---@return number # job id
function M.uninstall_app_from_device(destination, bundleId, callback)
  local command = { "xcrun", "devicectl", "device", "uninstall", "app", "-d", destination, bundleId }
  debug_print("uninstall_app_from_device", command)

  return vim.fn.jobstart(command, {
    stderr_buffered = true,
    on_stderr = show_stderr_output,
    on_exit = callback_or_error("uninstall", callback),
  })
end

---Uninstalls the application on the given platform and destination.
---@param platform string
---@param destination string
---@param bundleId string
---@param callback function|nil
---@return number # job id
function M.uninstall_app(platform, destination, bundleId, callback)
  if constants.is_simulator(platform) then
    return M.uninstall_app_from_simulator(destination, bundleId, callback)
  else
    return M.uninstall_app_from_device(destination, bundleId, callback)
  end
end

---Gets the pid of the application.
---Works only with simulator.
---@param productName string
---@param platform PlatformId|nil
---@return number|nil # pid
function M.get_app_pid(productName, platform)
  if platform == constants.Platform.MACOS then
    local pid = util.shell(
      "ps aux | grep '" .. productName .. ".app/Contents/MacOS' | grep -v grep | awk '{ print$2 }'"
    )

    return tonumber(pid and pid[1] or nil)
  end

  local pid = util.shell(
    "ps aux | grep '" .. productName .. ".app' | grep -v grep | grep -v 'Contents/MacOS' | awk '{ print$2 }'"
  )

  return tonumber(pid and pid[1] or nil)
end

---Kills the application.
---Works only with simulator.
---@param productName string
---@param platform PlatformId|nil
---@param callback function|nil
function M.kill_app(productName, platform, callback)
  local pid = M.get_app_pid(productName, platform)

  if pid then
    util.shell({ "kill", "-9", tostring(pid) })
  end

  util.call(callback)
end

---Gets the code coverage for the given {filepath}.
---@param xctestresultPath string
---@param filepath string # file to check
---@param callback fun(coverageData: string[])
---@return number # job id
function M.get_code_coverage(xctestresultPath, filepath, callback)
  local command = { "xcrun", "xccov", "view", "--archive", "--file", filepath, xctestresultPath }
  debug_print("get_code_coverage", command)

  return vim.fn.jobstart(command, {
    stdout_buffered = true,
    on_stdout = function(_, output)
      callback(output)
    end,
    on_exit = function() end,
  })
end

---Returns the list of tests for the given project.
---@param opts XcodeEnumerateOptions
---@param callback fun(tests: XcodeTest[])
---@return number # job id
function M.enumerate_tests(opts, callback)
  local appdata = require("xcodebuild.project.appdata")
  local outputPath = appdata.tests_filepath
  util.shell({ "rm", "-rf", outputPath })

  local command = {
    "xcodebuild",
    "test-without-building",
    "-enumerate-tests",
    "-scheme",
    opts.scheme,
    "-destination",
    "id=" .. opts.destination,
    get_project_param(opts.projectFile),
    opts.projectFile,
    opts.testPlan and "-testPlan" or nil,
    opts.testPlan,
    "-test-enumeration-format",
    "json",
    "-test-enumeration-output-path",
    outputPath,
    "-disableAutomaticPackageResolution",
    "-skipPackageUpdates",
    "-test-enumeration-style",
    "flat",
  }
  command = util.merge_array(command, opts.extraTestArgs)
  command = util.skip_nil(command)
  command = xcodebuildOffline.wrap_command_if_needed(command)
  debug_print("enumerate_tests", command)

  return vim.fn.jobstart(command, {
    cwd = opts.workingDirectory,
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

---Exports the code coverage report from the given {xcresultPath}
---to the {outputPath}.
---Reports is exported in the JSON format.
---@param xcresultPath string
---@param outputPath string
---@param callback function|nil
---@return number # job id
function M.export_code_coverage_report(xcresultPath, outputPath, callback)
  local command = { "xcrun", "xccov", "view", "--report", "--json", xcresultPath }
  debug_print("export_code_coverage_report", command)

  return vim.fn.jobstart(command, {
    stdout_buffered = true,
    on_stdout = function(_, output)
      if #output == 0 or (#output == 1 and output[1] == "") then
        return
      end
      vim.fn.writefile(output, outputPath)
    end,
    on_exit = function()
      util.call(callback)
    end,
  })
end

---Runs tests with the given options.
---@param opts XcodeTestOptions
---@return number # job id
function M.run_tests(opts)
  local appdata = require("xcodebuild.project.appdata")
  vim.fn.delete(appdata.test_xcresult_filepath, "rf")

  local command = {
    "xcodebuild",
    opts.withoutBuilding and "test-without-building" or "test",
    "-scheme",
    opts.scheme,
    "-destination",
    "id=" .. opts.destination,
    get_project_param(opts.projectFile),
    opts.projectFile,
    opts.testPlan and "-testPlan" or nil,
    opts.testPlan,
    "-resultBundlePath",
    appdata.test_xcresult_filepath,
  }
  command = util.merge_array(command, opts.extraTestArgs)
  command = util.skip_nil(command)
  command = xcodebuildOffline.wrap_command_if_needed(command)

  -- Disable parallel testing for Swift Packages
  -- There are issues with the logs order.
  if not opts.projectFile then
    table.insert(command, "-parallel-testing-enabled")
    table.insert(command, "NO")
  end

  if opts.testsToRun then
    for _, test in ipairs(opts.testsToRun) do
      table.insert(command, "-only-testing")
      table.insert(command, test)
    end
  end

  debug_print("run_tests", command)

  return vim.fn.jobstart(command, {
    cwd = opts.workingDirectory,
    stdout_buffered = false,
    stderr_buffered = false,
    on_stdout = opts.on_stdout,
    on_stderr = opts.on_stderr,
    on_exit = opts.on_exit,
  })
end

return M
