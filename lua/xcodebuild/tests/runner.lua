---@mod xcodebuild.tests.runner Test Runner
---@brief [[
---This module contains the functionality to run tests.
---
---It interacts with multiple modules to build, run, and
---present test results.
---@brief ]]

local util = require("xcodebuild.util")
local helpers = require("xcodebuild.helpers")

local notifications = require("xcodebuild.broadcasting.notifications")
local events = require("xcodebuild.broadcasting.events")

local xcode = require("xcodebuild.core.xcode")
local config = require("xcodebuild.core.config").options

local appdata = require("xcodebuild.project.appdata")
local projectConfig = require("xcodebuild.project.config")
local projectBuilder = require("xcodebuild.project.builder")

local diagnostics = require("xcodebuild.tests.diagnostics")
local testSearch = require("xcodebuild.tests.search")
local testExplorer = require("xcodebuild.tests.explorer")
local testProvider = require("xcodebuild.tests.provider")
local snapshots = require("xcodebuild.tests.snapshots")

local M = {}
local CANCELLED_CODE = 143

---@type string[]|nil test ids
local last_test_run

---Fixes the test report and updates the Test Explorer.
local function fix_test_report()
  local xcresultParser = require("xcodebuild.tests.xcresult_parser")
  local explorerConfig = require("xcodebuild.core.config").options.test_explorer

  if appdata.report and xcresultParser.fill_xcresult_data(appdata.report) then
    testExplorer.clear()
    testExplorer.start_tests()
    local testsToUpdate = {}
    local backup = explorerConfig.cursor_follows_tests

    for _, tests in pairs(appdata.report.tests) do
      for _, test in ipairs(tests) do
        table.insert(testsToUpdate, {
          id = test.target .. "/" .. test.class .. "/" .. test.name,
          status = test.success and "passed" or "failed",
          filepath = test.filepath,
          lineNumber = test.lineNumber,
          swiftTestingId = test.swiftTestingId,
        })
      end
    end

    table.sort(testsToUpdate, function(a, b)
      return a.id:lower() < b.id:lower()
    end)

    explorerConfig.cursor_follows_tests = false

    for _, test in ipairs(testsToUpdate) do
      testExplorer.update_test_status(test.id, test.status, {
        filepath = test.filepath,
        lineNumber = test.lineNumber,
        swiftTestingId = test.swiftTestingId,
      })
    end

    testExplorer.finish_tests()
    explorerConfig.cursor_follows_tests = backup
  end
end

---Builds application, enumerates tests, and loads
---them into the Test Explorer.
function M.reload_tests()
  local runBuild = function(completion)
    projectBuilder.build_project({ buildForTesting = true, doNotShowSuccess = true }, function(report)
      if util.is_empty(report.buildErrors) then
        util.call(completion)
      end
    end)
  end

  runBuild(function()
    notifications.send("Loading Tests...")

    M.currentJobId = xcode.enumerate_tests({
      workingDirectory = projectConfig.settings.workingDirectory,
      destination = projectConfig.settings.destination,
      projectFile = projectConfig.settings.projectFile,
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
      else
        testExplorer.load_tests(tests)
      end

      notifications.send("")
    end)
  end)
end

---Runs the provided {testsToRun} and shows the Test Explorer.
---If {testsToRun} is nil, it runs all tests.
---
---This is a core function to run tests. It coordinates
---the build, test run, and the presentation of the results.
---
---It sets logs, diagnostics, quickfix list, coverage,
---snapshot previews, and Test Explorer.
---@param testsToRun string[]|nil test ids
function M.run_tests(testsToRun)
  if not helpers.validate_project(false) then
    return
  end

  last_test_run = testsToRun
  notifications.send_tests_started()
  helpers.clear_state()
  diagnostics.clear_marks()

  local logsParser = require("xcodebuild.xcode_logs.parser")
  local quickfix = require("xcodebuild.core.quickfix")
  local logsPanel = require("xcodebuild.xcode_logs.panel")
  local coverage = require("xcodebuild.code_coverage.coverage")

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

      if not appdata.report.xcresultFilepath then
        notifications.send_warning("Could not find xcresult file. Code coverage won't be displayed.")
        return
      end

      coverage.export_coverage(appdata.report.xcresultFilepath, function()
        coverage.refresh_all_buffers()
        process_snapshots()
      end)
    else
      process_snapshots()
    end
  end

  local on_stdout = function(_, output)
    appdata.report = logsParser.parse_logs(output)
    notifications.show_tests_progress(appdata.report)

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
      logsParser.clear()
      logsPanel.append_log_lines({ "", "Tests cancelled" }, false)
      return
    end

    notifications.send_progress("Processing logs...")

    fix_test_report()

    if config.restore_on_start then
      appdata.write_report(appdata.report)
    end

    testSearch.load_targets_map()
    quickfix.set(appdata.report)
    diagnostics.refresh_all_test_buffers(appdata.report)
    logsPanel.set_logs(appdata.report, true, process_coverage)

    events.tests_finished(
      appdata.report.testsCount - appdata.report.failedTestsCount,
      appdata.report.failedTestsCount,
      false
    )
  end

  events.tests_started()

  projectBuilder.build_project({ buildForTesting = true, doNotShowSuccess = true }, function(report)
    if not util.is_empty(report.buildErrors) then
      return
    end

    testExplorer.start_tests(testsToRun)
    logsParser.clear()

    M.currentJobId = xcode.run_tests({
      on_exit = on_exit,
      on_stdout = on_stdout,
      on_stderr = on_stdout,

      withoutBuilding = true,
      workingDirectory = projectConfig.settings.workingDirectory,
      destination = projectConfig.settings.destination,
      projectFile = projectConfig.settings.projectFile,
      scheme = projectConfig.settings.scheme,
      testPlan = projectConfig.settings.testPlan,
      testsToRun = testsToRun,
      extraTestArgs = config.commands.extra_test_args,
    })
  end)
end

---@class TestRunnerOptions
---@field doNotBuild boolean|nil
---@field currentTarget boolean|nil
---@field currentClass boolean|nil
---@field currentTest boolean|nil
---@field selectedTests boolean|nil
---@field failingTests boolean|nil

---Runs only selected tests based on {opts}.
---If target is not found for the current buffer,
---it additionally triggers build for testing.
---@param opts TestRunnerOptions
function M.run_selected_tests(opts)
  if not helpers.validate_project(false) then
    return
  end

  local selectedClass, selectedTests
  if not opts.currentTarget then
    selectedClass, selectedTests = testProvider.find_tests({
      currentTest = opts.currentTest,
      selectedTests = opts.selectedTests,
      failingTests = opts.failingTests,
    })
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

---Repeats the last test run.
function M.repeat_last_test_run()
  M.run_tests(last_test_run)
end

---Shows a picker with failing snapshot tests.
function M.show_failing_snapshot_tests()
  if not helpers.validate_project(false) then
    return
  end

  local pickers = require("xcodebuild.ui.pickers")
  pickers.select_failing_snapshot_test()
end

return M
