local notifications = require("xcodebuild.notifications")
local parser = require("xcodebuild.parser")
local util = require("xcodebuild.util")
local appdata = require("xcodebuild.appdata")
local quickfix = require("xcodebuild.quickfix")
local projectConfig = require("xcodebuild.project_config")
local xcode = require("xcodebuild.xcode")
local logs = require("xcodebuild.logs")
local diagnostics = require("xcodebuild.diagnostics")
local config = require("xcodebuild.config").options
local snapshots = require("xcodebuild.snapshots")
local testSearch = require("xcodebuild.test_search")

local M = {
  report = {},
  currentJobId = nil,
}
local CANCELLED_CODE = 143

local function validate_project()
  if not projectConfig.is_project_configured() then
    notifications.send_error("The project is missing some details. Please run XcodebuildSetup first.")
    return false
  end

  return true
end

local function validate_testplan()
  if not projectConfig.settings.testPlan then
    notifications.send_error("Test plan not found. Please run XcodebuildSelectTestPlan")
    return false
  end

  return true
end

function M.auto_save()
  if config.auto_save then
    vim.cmd("silent wa!")
  end
end

function M.show_current_config()
  if not validate_project() then
    return
  end

  vim.defer_fn(function()
    notifications.send_project_settings(projectConfig.settings)
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
  if M.currentJobId then
    vim.fn.jobstop(M.currentJobId)
    M.currentJobId = nil
  end
end

function M.load_last_report()
  parser.clear()
  M.report = appdata.read_report() or {}

  if util.is_not_empty(M.report) then
    vim.defer_fn(function()
      testSearch.load_targets_map()
      quickfix.set(M.report)
      diagnostics.refresh_all_test_buffers(M.report)
    end, vim.startswith(config.test_search.file_matching, "lsp") and 1000 or 500)
  end
end

function M.build_and_run_app(waitForDebugger, callback)
  if not validate_project() then
    return
  end

  M.build_project({}, function(report)
    if util.is_not_empty(report.buildErrors) then
      notifications.send_error("Build Failed")
      logs.open_logs(true)
      return
    end

    M.run_app(waitForDebugger, callback)
  end)
end

function M.run_app(waitForDebugger, callback)
  if not validate_project() then
    return
  end

  if config.logs.auto_close_on_app_launch then
    logs.close_logs()
  end

  local settings = projectConfig.settings

  if settings.platform == "macOS" then
    notifications.send("Launching application...")
    local path = settings.appPath .. "/Contents/MacOS/" .. settings.productName

    M.currentJobId = vim.fn.jobstart(path, { detach = true })
    notifications.send("Application has been launched")

    if callback then
      callback()
    end
  else
    if settings.productName then
      xcode.kill_app(settings.productName)
    end

    notifications.send("Installing application...")
    M.currentJobId = xcode.install_app(settings.destination, settings.appPath, function()
      notifications.send("Launching application...")
      M.currentJobId = xcode.launch_app(settings.destination, settings.bundleId, waitForDebugger, function()
        notifications.send("Application has been launched")

        if callback then
          callback()
        end
      end)
    end)
  end
end

function M.boot_simulator(callback)
  if not validate_project() then
    return
  end

  if projectConfig.settings.platform == "macOS" then
    notifications.send_error("Your selected device is macOS.")
    return
  end

  notifications.send("Booting simulator...")
  xcode.boot_simulator(projectConfig.settings.destination, function()
    notifications.send("Simulator booted")

    if callback then
      callback()
    end
  end)
end

function M.uninstall_app(callback)
  if not validate_project() then
    return
  end

  local settings = projectConfig.settings
  if settings.platform == "macOS" then
    notifications.send_error("macOS apps cannot be uninstalled")
    return
  end

  notifications.send("Uninstalling application...")
  M.currentJobId = xcode.uninstall_app(settings.destination, settings.bundleId, function()
    notifications.send("Application has been uninstalled")

    if callback then
      callback()
    end
  end)
end

function M.build_project(opts, callback)
  opts = opts or {}

  if not validate_project() then
    return
  end

  local buildId = notifications.send_build_started(opts.buildForTesting)
  M.auto_save()
  snapshots.delete_snapshots()
  parser.clear()

  local on_stdout = function(_, output)
    M.report = parser.parse_logs(output)
  end

  local on_exit = function(_, code, _)
    if code == CANCELLED_CODE then
      notifications.send_build_finished(M.report, buildId, true)
      return
    end

    if config.restore_on_start then
      appdata.write_report(M.report)
    end

    quickfix.set(M.report)

    notifications.stop_build_timer()
    notifications.send_progress("Processing logs...")
    logs.set_logs(M.report, false, function()
      notifications.send_build_finished(M.report, buildId, false)
    end)

    if callback then
      callback(M.report)
    end
  end

  M.currentJobId = xcode.build_project({
    on_exit = on_exit,
    on_stdout = on_stdout,
    on_stderr = on_stdout,

    buildForTesting = opts.buildForTesting,
    clean = opts.clean,
    destination = projectConfig.settings.destination,
    projectCommand = projectConfig.settings.projectCommand,
    scheme = projectConfig.settings.scheme,
    config = projectConfig.settings.config,
    testPlan = projectConfig.settings.testPlan,
    extraBuildArgs = config.commands.extra_build_args,
  })
end

function M.run_tests(testsToRun)
  if not validate_project() or not validate_testplan() then
    return
  end

  notifications.send_tests_started()
  M.auto_save()
  snapshots.delete_snapshots()
  parser.clear()

  local on_stdout = function(_, output)
    M.report = parser.parse_logs(output)
    notifications.show_tests_progress(M.report)
    diagnostics.refresh_all_test_buffers(M.report)
  end

  local on_exit = function(_, code, _)
    if code == CANCELLED_CODE then
      notifications.send_tests_finished(M.report, true)
      return
    end

    if config.restore_on_start then
      appdata.write_report(M.report)
    end

    testSearch.load_targets_map()
    quickfix.set(M.report)
    diagnostics.refresh_all_test_buffers(M.report)

    notifications.send_progress("Processing logs...")
    logs.set_logs(M.report, true, function()
      if M.report.failedTestsCount > 0 and config.prepare_snapshot_test_previews then
        notifications.send_progress("Processing snapshots...")
        snapshots.save_failing_snapshots(M.report.xcresultFilepath, function()
          notifications.send_tests_finished(M.report, false)
        end)
      else
        notifications.send_tests_finished(M.report, false)
      end
    end)
  end

  M.currentJobId = xcode.run_tests({
    on_exit = on_exit,
    on_stdout = on_stdout,
    on_stderr = on_stdout,

    destination = projectConfig.settings.destination,
    projectCommand = projectConfig.settings.projectCommand,
    scheme = projectConfig.settings.scheme,
    config = projectConfig.settings.config,
    testPlan = projectConfig.settings.testPlan,
    testsToRun = testsToRun,
    extraTestArgs = config.commands.extra_test_args,
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
  elseif opts.failingTests and M.report.failedTestsCount > 0 then
    for _, testsPerClass in pairs(M.report.tests) do
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

function M.run_selected_tests(opts)
  if not validate_project() or not validate_testplan() then
    return
  end

  local selectedClass, selectedTests = find_tests(opts)

  local start = function()
    local testsToRun = {}
    local testFilepath = vim.api.nvim_buf_get_name(0)
    local target = testSearch.find_target_for_file(testFilepath)

    if not target then
      notifications.send_error("Could not detect test target. Please run build again.")
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
        local testTarget = testSearch.find_target_for_file(test.filepath)
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
  testSearch.load_targets_map()

  if util.is_empty(testSearch.targetsFilesMap) then
    notifications.send("Loading tests...")
    M.currentJobId = M.build_project({
      buildForTesting = true,
    }, function()
      testSearch.load_targets_map()
      start()
    end)
  else
    start()
  end
end

function M.show_failing_snapshot_tests()
  if not validate_project() then
    return
  end

  local pickers = require("xcodebuild.pickers")
  pickers.select_failing_snapshot_test()
end

function M.clean_derived_data()
  local appPath = projectConfig.settings.appPath
  if not appPath then
    notifications.send_error("Could not detect DerivedData. Please build project.")
    return
  end

  local derivedDataPath = string.match(appPath, "(.+/DerivedData/[^/]+)/.+")
  if not derivedDataPath then
    notifications.send_error("Could not detect DerivedData. Please build project.")
    return
  end

  local dir = string.match(derivedDataPath, "/([^/]+)$")

  vim.defer_fn(function()
    vim.ui.input({ prompt = "Delete " .. dir .. "? [y/n]" }, function(input)
      if input == "y" then
        util.shell("rm -rf '" .. derivedDataPath .. "' 2>/dev/null")
        notifications.send("Deleted: " .. derivedDataPath)
      end
    end)
  end, 200)
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
    pickers.select_xcodeproj_if_needed(function()
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
  end)
end

return M
