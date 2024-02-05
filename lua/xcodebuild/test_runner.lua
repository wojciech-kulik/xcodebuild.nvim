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
local coverage = require("xcodebuild.coverage")
local testExplorer = require("xcodebuild.test_explorer")
local events = require("xcodebuild.events")
local projectBuilder = require("xcodebuild.project_builder")
local testProvider = require("xcodebuild.test_provider")
local helpers = require("xcodebuild.helpers")

local M = {}
local CANCELLED_CODE = 143

local function validate_testplan()
  if not projectConfig.settings.testPlan then
    notifications.send_error("Test plan not found. Please run XcodebuildSelectTestPlan")
    return false
  end

  return true
end

function M.show_test_explorer(callback, opts)
  opts = opts or {}

  local runBuild = function(completion)
    projectBuilder.build_project({ buildForTesting = true, doNotShowSuccess = true }, function(report)
      if util.is_empty(report.buildErrors) then
        util.call(completion)
      end
    end)
  end

  local show = function()
    if config.test_explorer.auto_open then
      testExplorer.show()
    end

    util.call(callback)
  end

  if not config.test_explorer.enabled then
    runBuild(callback)
    return
  end

  if opts.skipEnumeration then
    runBuild(function()
      testExplorer.finish_tests()
      show()
    end)
    return
  end

  runBuild(function()
    notifications.send("Loading Tests...")

    M.currentJobId = xcode.enumerate_tests({
      destination = projectConfig.settings.destination,
      config = projectConfig.settings.config,
      projectCommand = projectConfig.settings.projectCommand,
      scheme = projectConfig.settings.scheme,
      testPlan = projectConfig.settings.testPlan,
      extraTestArgs = config.commands.extra_test_args,
    }, function(tests)
      -- workaround sometimes after cancel enumerate tests returns 0 code
      if not M.currentJobId then
        return
      end

      if util.is_empty(tests) then
        notifications.send_error("Tests not found")
        util.call(callback)
      else
        testExplorer.load_tests(tests)
        show()
      end
    end)
  end)
end

function M.run_tests(testsToRun, opts)
  opts = opts or {}

  if not helpers.validate_project() or not validate_testplan() then
    return
  end

  notifications.send_tests_started()
  helpers.before_new_run()

  local show_finish = function()
    notifications.send_tests_finished(appdata.report, false)
  end

  local process_snapshots = function()
    if appdata.report.failedTestsCount > 0 and config.prepare_snapshot_test_previews then
      notifications.send_progress("Processing snapshots...")

      snapshots.save_failing_snapshots(appdata.report.xcresultFilepath, show_finish)
    else
      show_finish()
    end
  end

  local process_coverage = function()
    if config.code_coverage.enabled then
      notifications.send_progress("Gathering coverage...")

      coverage.export_coverage(appdata.report.xcresultFilepath, function()
        coverage.refresh_all_buffers()
        process_snapshots()
      end)
    else
      process_snapshots()
    end
  end

  local on_stdout = function(_, output)
    appdata.report = parser.parse_logs(output)
    notifications.show_tests_progress(appdata.report)
    diagnostics.refresh_all_test_buffers(appdata.report)
    events.tests_status(
      appdata.report.testsCount - appdata.report.failedTestsCount,
      appdata.report.failedTestsCount
    )
  end

  local on_exit = function(_, code, _)
    testExplorer.finish_tests()

    if code == CANCELLED_CODE then
      notifications.send_tests_finished(appdata.report, true)
      events.tests_finished(
        appdata.report.testsCount - appdata.report.failedTestsCount,
        appdata.report.failedTestsCount,
        true
      )
      return
    end

    if config.restore_on_start then
      appdata.write_report(appdata.report)
    end

    testSearch.load_targets_map()
    quickfix.set(appdata.report)
    diagnostics.refresh_all_test_buffers(appdata.report)

    notifications.send_progress("Processing logs...")
    logs.set_logs(appdata.report, true, process_coverage)

    events.tests_finished(
      appdata.report.testsCount - appdata.report.failedTestsCount,
      appdata.report.failedTestsCount,
      false
    )
  end

  events.tests_started()

  -- Test Explorer also builds for testing
  M.show_test_explorer(function()
    testExplorer.start_tests(testsToRun)

    M.currentJobId = xcode.run_tests({
      on_exit = on_exit,
      on_stdout = on_stdout,
      on_stderr = on_stdout,

      withoutBuilding = true,
      destination = projectConfig.settings.destination,
      projectCommand = projectConfig.settings.projectCommand,
      scheme = projectConfig.settings.scheme,
      config = projectConfig.settings.config,
      testPlan = projectConfig.settings.testPlan,
      testsToRun = testsToRun,
      extraTestArgs = config.commands.extra_test_args,
    })
  end, opts)
end

function M.run_selected_tests(opts)
  if not helpers.validate_project() or not validate_testplan() then
    return
  end

  local selectedClass, selectedTests
  if not opts.currentTarget then
    selectedClass, selectedTests = testProvider.find_tests(opts)
  end

  local start = function()
    local testsToRun = {}
    local testFilepath = vim.api.nvim_buf_get_name(0)
    local target = testSearch.find_target_for_file(testFilepath)

    if not target then
      if opts.doNotBuild then
        notifications.send_error("Could not detect test target. Please run build for testing.")
      else
        opts.doNotBuild = true
        projectBuilder.build_project({ buildForTesting = true }, function()
          M.run_selected_tests(opts)
        end)
      end
      return
    end

    if opts.currentTarget then
      table.insert(testsToRun, target)
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
    M.currentJobId = projectBuilder.build_project({ buildForTesting = true }, function()
      opts.doNotBuild = true
      testSearch.load_targets_map()
      start()
    end)
  else
    start()
  end
end

function M.show_failing_snapshot_tests()
  if not helpers.validate_project() then
    return
  end

  local pickers = require("xcodebuild.pickers")
  pickers.select_failing_snapshot_test()
end

return M
