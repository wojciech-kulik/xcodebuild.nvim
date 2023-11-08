local notifications = require("xcodebuild.notifications")
local parser = require("xcodebuild.parser")
local util = require("xcodebuild.util")
local appdata = require("xcodebuild.appdata")
local quickfix = require("xcodebuild.quickfix")
local projectConfig = require("xcodebuild.project_config")
local xcode = require("xcodebuild.xcode")
local logs = require("xcodebuild.logs")
local diagnostics = require("xcodebuild.diagnostics")

local M = {}
local testReport = {}
local currentJobId = nil
local targetToFiles = {}

local function validate_project()
  if not require("xcodebuild.project_config").is_project_configured() then
    notifications.send_error("The project is missing some details. Please run XcodebuildSetup first.")
    return false
  end

  return true
end

local function validate_testplan()
  if not require("xcodebuild.project_config").settings.testPlan then
    notifications.send_error("Test plan not found. Please run XcodebuilSelectTestPlan")
    return false
  end

  return true
end

function M.show_current_config()
  if not validate_project() then
    return
  end

  local settings = projectConfig.settings
  vim.defer_fn(function()
    notifications.send([[
      Project Configuration

      - platform: ]] .. settings.platform .. [[

      - project: ]] .. settings.projectFile .. [[

      - scheme: ]] .. settings.scheme .. [[

      - config: ]] .. settings.config .. [[

      - destination: ]] .. settings.destination .. [[

      - testPlan: ]] .. (settings.testPlan or "") .. [[

      - bundleId: ]] .. settings.bundleId .. [[

      - appPath: ]] .. settings.appPath .. [[

      - productName: ]] .. settings.productName .. [[
    ]])
  end, 100)
end

function M.update_settings(callback)
  local settings = projectConfig.settings

  xcode.get_build_settings(
    settings.platform,
    settings.projectCommand,
    settings.scheme,
    settings.config,
    function(buildSettings)
      projectConfig.settings.appPath = buildSettings.appPath
      projectConfig.settings.productName = buildSettings.productName
      projectConfig.settings.bundleId = buildSettings.bundleId
      projectConfig.save_settings()
      if callback then
        callback()
      end
    end
  )
end

function M.cancel()
  if currentJobId then
    vim.fn.jobstop(currentJobId)
    currentJobId = nil
  end
end

function M.get_report()
  return testReport
end

function M.load_last_report()
  local success, log = pcall(appdata.read_original_logs)

  if success then
    parser.clear()
    testReport = parser.parse_logs(log)
    quickfix.set(testReport)
    vim.defer_fn(function()
      diagnostics.refresh_all_test_buffers(testReport)
    end, 500)
  end
end

function M.build_and_run_app(callback)
  if not validate_project() then
    return
  end

  M.build_project(false, function(report)
    if report.buildErrors and report.buildErrors[1] then
      notifications.send_error("Build Failed")
      logs.open_logs(true)
      return
    end

    M.run_app(callback)
  end)
end

function M.run_app(callback)
  if not validate_project() then
    return
  end

  local settings = projectConfig.settings

  if settings.platform == "macOS" then
    notifications.send("Launching application...")
    local app = string.match(settings.appPath, "/([^/]+)%.app$")
    local path = settings.appPath .. "/Contents/MacOS/" .. app
    currentJobId = vim.fn.jobstart(path, {
      detach = true,
    })
    notifications.send("Application has been launched")
    if callback then
      callback()
    end
  else
    local destination = settings.destination
    local productName = settings.productName

    if productName then
      xcode.kill_app(productName)
    end

    notifications.send("Installing application...")
    currentJobId = xcode.install_app(destination, settings.appPath, function()
      notifications.send("Launching application...")
      currentJobId = xcode.launch_app(destination, settings.bundleId, function()
        notifications.send("Application has been launched")
        if callback then
          callback()
        end
      end)
    end)
  end
end

function M.uninstall_app(callback)
  if not validate_project() then
    return
  end

  local settings = projectConfig.settings
  if settings.platform == "macOS" then
    notifications.send_error("macOS app doesn't require uninstalling")
    return
  end

  notifications.send("Uninstalling application...")
  currentJobId = xcode.uninstall_app(settings.destination, settings.bundleId, function()
    notifications.send("Application has been uninstalled")
    if callback then
      callback()
    end
  end)
end

function M.auto_save()
  local config = require("xcodebuild.config").options
  if config.auto_save then
    vim.cmd("silent wa!")
  end
end

function M.build_project(buildForTesting, callback)
  if not validate_project() then
    return
  end

  local lastBuildTime = projectConfig.settings.lastBuildTime
  local progressTimer = not buildForTesting and notifications.start_action_timer("Building", lastBuildTime)
  local startTime = os.time()

  M.auto_save()
  parser.clear()

  local on_stdout = function(_, output)
    testReport = parser.parse_logs(output)
  end

  local on_stderr = function(_, output)
    testReport = parser.parse_logs(output)
  end

  local on_exit = function(_, code, _)
    if progressTimer then
      vim.fn.timer_stop(progressTimer)
    end

    if code == 143 then
      return
    end

    vim.cmd("echo ''")
    logs.set_logs(testReport, false)
    quickfix.set(testReport)

    if util.is_empty(testReport.buildErrors) then
      local duration = os.difftime(os.time(), startTime)
      projectConfig.settings.lastBuildTime = duration
      projectConfig.save_settings()
      notifications.send(string.format("Build Succeeded [%d seconds]", duration))
    else
      notifications.send_error("Build Failed [" .. #testReport.buildErrors .. " error(s)]")
    end

    if callback then
      callback(testReport)
    end
  end

  currentJobId = xcode.build_project({
    on_exit = on_exit,
    on_stdout = on_stdout,
    on_stderr = on_stderr,

    buildForTesting = buildForTesting,
    destination = projectConfig.settings.destination,
    projectCommand = projectConfig.settings.projectCommand,
    scheme = projectConfig.settings.scheme,
    config = projectConfig.settings.config,
    testPlan = projectConfig.settings.testPlan,
  })
end

function M.run_tests(testsToRun)
  if not validate_project() or not validate_testplan() then
    return
  end

  notifications.send("Starting Tests...")
  M.auto_save()
  parser.clear()

  local on_stdout = function(_, output)
    testReport = parser.parse_logs(output)
    notifications.show_tests_progress(testReport)
    diagnostics.refresh_all_test_buffers(testReport)
  end

  local on_stderr = function(_, output)
    testReport = parser.parse_logs(output)
  end

  local on_exit = function(_, code, _)
    if code == 143 then
      return
    end

    targetToFiles = xcode.get_targets_list(projectConfig.settings.appPath)
    logs.set_logs(testReport, true)
    notifications.print_tests_summary(testReport)
    quickfix.set_targets_filemap(targetToFiles)
    quickfix.set(testReport)
    diagnostics.refresh_all_test_buffers(testReport)
  end

  currentJobId = xcode.run_tests({
    on_exit = on_exit,
    on_stdout = on_stdout,
    on_stderr = on_stderr,

    destination = projectConfig.settings.destination,
    projectCommand = projectConfig.settings.projectCommand,
    scheme = projectConfig.settings.scheme,
    config = projectConfig.settings.config,
    testPlan = projectConfig.settings.testPlan,
    testsToRun = testsToRun,
  })
end

local function find_tests(opts)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local selectedClass = nil
  local selectedTests = {}

  for _, line in ipairs(lines) do
    selectedClass = string.match(line, "class ([^:%s]+)%s*%:?")
    if selectedClass then
      break
    end
  end

  if opts.selectedTests then
    local vstart = vim.fn.getpos("'<")
    local vend = vim.fn.getpos("'>")
    local lineStart = vstart[2]
    local lineEnd = vend[2]

    for i = lineStart, lineEnd do
      local test = string.match(lines[i], "func (test[^%s%(]+)")
      if test then
        table.insert(selectedTests, {
          name = test,
          class = selectedClass,
        })
      end
    end
  elseif opts.currentTest then
    local winnr = vim.api.nvim_get_current_win()
    local currentLine = vim.api.nvim_win_get_cursor(winnr)[1]

    for i = currentLine, 1, -1 do
      local test = string.match(lines[i], "func (test[^%s%(]+)")
      if test then
        table.insert(selectedTests, {
          name = test,
          class = selectedClass,
        })
        break
      end
    end
  elseif opts.failingTests and testReport.failedTestsCount > 0 then
    for _, testsPerClass in pairs(testReport.tests) do
      for _, test in ipairs(testsPerClass) do
        if not test.success then
          table.insert(selectedTests, {
            name = test.name,
            class = test.class,
            filepath = test.filepath,
          })
        end
      end
    end
  end

  return selectedClass, selectedTests
end

local function find_target_for_file(filepath)
  for target, files in pairs(targetToFiles) do
    if util.contains(files, filepath) then
      return target
    end
  end
end

function M.run_selected_tests(opts)
  if not validate_project() or not validate_testplan() then
    return
  end
  local selectedClass, selectedTests = find_tests(opts)

  local start = function()
    local testsToRun = {}
    local testFilepath = vim.api.nvim_buf_get_name(0)
    local target = find_target_for_file(testFilepath)

    if not target then
      notifications.send("Could not detect test target. Please run build again.")
      return
    end

    if opts.currentClass and selectedClass then
      table.insert(testsToRun, target .. "/" .. selectedClass)
    end

    if opts.currentTest or opts.selectedTests then
      for _, test in ipairs(selectedTests) do
        table.insert(testsToRun, target .. "/" .. test.class .. "/" .. test.name)
      end
    end

    if opts.failingTests then
      for _, test in ipairs(selectedTests) do
        local testTarget = find_target_for_file(test.filepath)
        if testTarget then
          table.insert(testsToRun, testTarget .. "/" .. test.class .. "/" .. test.name)
        end
      end
    end

    if next(testsToRun) then
      M.run_tests(testsToRun)
    else
      notifications.send_error("Tests not found")
    end
  end

  -- TODO: clear cache when a new swift test file is added
  if not targetToFiles or not next(targetToFiles) then
    notifications.send("Loading tests...")
    currentJobId = M.build_project(true, function()
      targetToFiles = xcode.get_targets_list(projectConfig.settings.appPath)
      quickfix.set_targets_filemap(targetToFiles)
      start()
    end)
  else
    start()
  end
end

function M.configure_project()
  appdata.create_app_dir()

  local pickers = require("xcodebuild.pickers")
  local defer_print = function(text)
    vim.defer_fn(function()
      notifications.send(text)
    end, 100)
  end

  pickers.select_project(function()
    defer_print("Loading project information...")
    pickers.select_config(function(projectInfo)
      pickers.select_scheme(projectInfo.schemes, function()
        defer_print("Loading devices...")
        pickers.select_destination(function()
          defer_print("Updating settings...")
          M.update_settings(function()
            defer_print("Loading test plans...")
            pickers.select_testplan(function()
              defer_print("Xcodebuild configuration has been saved!")
            end, { close_on_select = true })
          end)
        end)
      end)
    end)
  end)
end

return M
