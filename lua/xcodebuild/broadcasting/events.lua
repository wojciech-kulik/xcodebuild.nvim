---@mod xcodebuild.broadcasting.events Autocommand Events
---@tag xcodebuild.events
---@brief [[
---This module is responsible for broadcasting events about the build and
---tests status. It also updates some global variables to be used in the UI.
---
---You can customize integration with xcodebuild.nvim plugin by subscribing to notifications.
---
---Example:
--->lua
---    vim.api.nvim_create_autocmd("User", {
---      pattern = "XcodebuildTestsFinished",
---      callback = function(event)
---        print("Tests finished (passed: "
---            .. event.data.passedCount
---            .. ", failed: "
---            .. event.data.failedCount
---            .. ")"
---        )
---      end,
---    })
---<
---All available autocommand patterns:
---
--- | Pattern                          |
--- | -------------------------------- |
--- | `XcodebuildBuildStarted`           |
--- | `XcodebuildBuildStatus`            |
--- | `XcodebuildBuildFinished`          |
--- | `XcodebuildTestsStarted`           |
--- | `XcodebuildTestsStatus`            |
--- | `XcodebuildTestsFinished`          |
--- | `XcodebuildApplicationLaunched`    |
--- | `XcodebuildActionCancelled`        |
--- | `XcodebuildProjectSettingsUpdated` |
--- | `XcodebuildTestExplorerToggled`    |
--- | `XcodebuildCoverageToggled`        |
--- | `XcodebuildCoverageReportToggled`  |
--- | `XcodebuildLogsToggled`            |
---
---For payload details of each event, see the respective function.
---
---@brief ]]

local M = {}
local lastDuration = 0

---Notifies that the build has been started.
---It triggers the `XcodebuildBuildStarted` autocommand and clears the
---global variable `xcodebuild_last_status`.
---@param forTesting boolean if the build is for testing.
function M.build_started(forTesting)
  vim.api.nvim_exec_autocmds("User", {
    pattern = "XcodebuildBuildStarted",
    data = { forTesting = forTesting },
  })

  vim.g.xcodebuild_last_status = nil
end

---Notifies about the build progress.
---It triggers the `XcodebuildBuildStatus` autocommand and updates global
---variable `xcodebuild_last_status`.
---@param forTesting boolean if the build is for testing.
---@param progress number the progress percentage (0-100).
---@param duration number the duration of the build in seconds.
function M.build_status(forTesting, progress, duration)
  vim.api.nvim_exec_autocmds("User", {
    pattern = "XcodebuildBuildStatus",
    data = { forTesting = forTesting, progress = progress, duration = duration },
  })
  lastDuration = duration
  vim.g.xcodebuild_last_status = "Building" .. (forTesting and " For Testing..." or "...")
end

---Notifies that the build has been finished.
---It triggers the `XcodebuildBuildFinished` autocommand and updates global
---variable `xcodebuild_last_status`.
---@param forTesting boolean if the build is for testing.
---@param success boolean if the build was successful.
---@param cancelled boolean if the build was cancelled.
---@param errors ParsedBuildError[]|ParsedBuildGenericError[] build errors.
function M.build_finished(forTesting, success, cancelled, errors)
  vim.api.nvim_exec_autocmds("User", {
    pattern = "XcodebuildBuildFinished",
    data = { forTesting = forTesting, success = success, cancelled = cancelled, errors = errors },
  })

  if cancelled then
    vim.g.xcodebuild_last_status = "Build Cancelled"
  elseif success then
    vim.g.xcodebuild_last_status = "Build Succeeded [" .. lastDuration .. "s]"
  else
    vim.g.xcodebuild_last_status = "Build Failed With " .. #errors .. " Error(s)"
  end
end

---Notifies that tests have been started.
---It triggers the `XcodebuildTestsStarted` autocommand and clears the
---global variable `xcodebuild_last_status`.
function M.tests_started()
  vim.api.nvim_exec_autocmds("User", {
    pattern = "XcodebuildTestsStarted",
  })

  vim.g.xcodebuild_last_status = nil
end

---Notifies about tests progress.
---It triggers the `XcodebuildTestsStatus` autocommand and updates global
---variable `xcodebuild_last_status`.
---@param passedCount number the number of passed tests.
---@param failedCount number the number of failed tests.
function M.tests_status(passedCount, failedCount)
  vim.api.nvim_exec_autocmds("User", {
    pattern = "XcodebuildTestsStatus",
    data = { passedCount = passedCount, failedCount = failedCount },
  })
  vim.g.xcodebuild_last_status = "Running Tests..."
end

---Notifies that tests have been finished.
---It triggers the `XcodebuildTestsFinished` autocommand and updates global
---variable `xcodebuild_last_status`.
---@param passedCount number the number of passed tests.
---@param failedCount number the number of failed tests.
---@param cancelled boolean if tests were cancelled.
function M.tests_finished(passedCount, failedCount, cancelled)
  vim.api.nvim_exec_autocmds("User", {
    pattern = "XcodebuildTestsFinished",
    data = { passedCount = passedCount, failedCount = failedCount, cancelled = cancelled },
  })

  local success = failedCount == 0

  if cancelled then
    vim.g.xcodebuild_last_status = "Tests Cancelled"
  elseif success then
    vim.g.xcodebuild_last_status = "Tests Passed [Executed: " .. passedCount .. "]"
  else
    vim.g.xcodebuild_last_status = "Tests Failed [Passed: "
      .. passedCount
      .. " Failed: "
      .. failedCount
      .. "]"
  end
end

---Notifies that the application has been launched.
---It triggers the `XcodebuildApplicationLaunched` autocommand.
function M.application_launched()
  vim.api.nvim_exec_autocmds("User", {
    pattern = "XcodebuildApplicationLaunched",
  })
end

---Notifies that the last action has been cancelled.
---It triggers the `XcodebuildActionCancelled` autocommand.
function M.action_cancelled()
  vim.api.nvim_exec_autocmds("User", {
    pattern = "XcodebuildActionCancelled",
  })
end

---Notifies that the project settings have been updated.
---It triggers the `XcodebuildProjectSettingsUpdated` autocommand.
---@param settings ProjectSettings the updated settings.
function M.project_settings_updated(settings)
  vim.api.nvim_exec_autocmds("User", {
    pattern = "XcodebuildProjectSettingsUpdated",
    data = settings,
  })
end

---Notifies that the test explorer has been toggled.
---It triggers the `XcodebuildTestExplorerToggled` autocommand.
---@param visible boolean if the test explorer is visible.
---@param bufnr number|nil the buffer number with the test explorer.
---@param winnr number|nil the window number with the test explorer.
function M.toggled_test_explorer(visible, bufnr, winnr)
  vim.api.nvim_exec_autocmds("User", {
    pattern = "XcodebuildTestExplorerToggled",
    data = { visible = visible, bufnr = bufnr, winnr = winnr },
  })
end

---Notifies that the code coverage has been toggled.
---It triggers the `XcodebuildCoverageToggled` autocommand.
---@param visible boolean if the code coverage is visible.
function M.toggled_code_coverage(visible)
  vim.api.nvim_exec_autocmds("User", {
    pattern = "XcodebuildCoverageToggled",
    data = visible,
  })
end

---Notifies that the code coverage report has been toggled.
---It triggers the `XcodebuildCoverageReportToggled` autocommand.
---@param visible boolean if the code coverage report is visible.
---@param bufnr number|nil the buffer number with the report.
---@param winnr number|nil the window number with the report.
function M.toggled_code_coverage_report(visible, bufnr, winnr)
  vim.api.nvim_exec_autocmds("User", {
    pattern = "XcodebuildCoverageReportToggled",
    data = { visible = visible, bufnr = bufnr, winnr = winnr },
  })
end

---Notifies that the logs have been toggled.
---It triggers the `XcodebuildLogsToggled` autocommand.
---@param visible boolean if the logs are visible.
---@param bufnr number|nil the buffer number with logs.
---@param winnr number|nil the window number with logs.
function M.toggled_logs(visible, bufnr, winnr)
  vim.api.nvim_exec_autocmds("User", {
    pattern = "XcodebuildLogsToggled",
    data = { visible = visible, bufnr = bufnr, winnr = winnr },
  })
end

return M
