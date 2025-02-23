---@mod xcodebuild.project.builder Project Builder
---@brief [[
---This module contains the functionality to build the project.
---
---It interacts with multiple modules to build the project
---and present the results.
---
---It also sends notifications and events to the user.
---@brief ]]

local util = require("xcodebuild.util")
local helpers = require("xcodebuild.helpers")
local notifications = require("xcodebuild.broadcasting.notifications")
local events = require("xcodebuild.broadcasting.events")
local appdata = require("xcodebuild.project.appdata")
local projectConfig = require("xcodebuild.project.config")
local config = require("xcodebuild.core.config").options

local M = {}
local CANCELLED_CODE = 143

---Builds and runs the app on device or simulator.
---@param waitForDebugger boolean
---@param callback function|nil
---@see xcodebuild.platform.device.run_app
---@see xcodebuild.project.builder.build_project
function M.build_and_run_app(waitForDebugger, callback)
  if not helpers.validate_project({ requiresApp = true }) then
    return
  end

  M.build_project({}, function(report)
    if util.is_not_empty(report.buildErrors) then
      notifications.send_error("Build Failed")
      return
    end

    local device = require("xcodebuild.platform.device")
    device.run_app(waitForDebugger, callback)
  end)
end

---Builds the project.
---Sets quickfix list, logs, and sends notifications.
---@param opts table|nil
---
---* {buildForTesting} (boolean|nil)
---* {doNotShowSuccess} (boolean|nil)
---  if should send the notification
---* {clean} (boolean|nil) runs clean build
---@param callback function|nil
---@see xcodebuild.core.xcode.build_project
function M.build_project(opts, callback)
  opts = opts or {}

  if not helpers.validate_project() then
    return
  end

  local quickfix = require("xcodebuild.core.quickfix")
  local logsParser = require("xcodebuild.xcode_logs.parser")
  local xcode = require("xcodebuild.core.xcode")
  local logsPanel = require("xcodebuild.xcode_logs.panel")

  local buildId = notifications.start_build_timer(opts.buildForTesting)
  helpers.clear_state()

  local on_stdout = function(_, output)
    appdata.report = logsParser.parse_logs(output)
  end

  local on_exit = function(_, code, _)
    if code == CANCELLED_CODE then
      notifications.send_build_finished(appdata.report, buildId, true)
      events.build_finished(opts.buildForTesting or false, false, true, {})
      logsParser.clear()
      logsPanel.append_log_lines({ "", "Build cancelled" }, false)
      return
    end

    if config.restore_on_start then
      appdata.write_report(appdata.report)
    end

    quickfix.set(appdata.report)

    notifications.stop_build_timer()
    notifications.send_progress("Processing logs...")
    logsPanel.set_logs(appdata.report, false, function()
      notifications.send_build_finished(
        appdata.report,
        buildId,
        false,
        { doNotShowSuccess = opts.doNotShowSuccess }
      )
    end)

    util.call(callback, appdata.report)

    events.build_finished(
      opts.buildForTesting or false,
      util.is_empty(appdata.report.buildErrors),
      false,
      appdata.report.buildErrors
    )
  end

  events.build_started(opts.buildForTesting or false)

  M.currentJobId = xcode.build_project({
    on_exit = on_exit,
    on_stdout = on_stdout,
    on_stderr = on_stdout,

    buildForTesting = opts.buildForTesting,
    clean = opts.clean,
    workingDirectory = projectConfig.settings.workingDirectory,
    destination = projectConfig.settings.destination,
    projectFile = projectConfig.settings.projectFile,
    scheme = projectConfig.settings.scheme,
    extraBuildArgs = config.commands.extra_build_args,
  })
end

---Cleans the `DerivedData` folder.
---It will ask for confirmation before deleting it.
function M.clean_derived_data()
  local derivedDataPath

  if projectConfig.settings.buildDir then
    local buildDir = projectConfig.settings.buildDir or ""
    derivedDataPath = string.match(buildDir, "(.+/DerivedData/[^/]+)/.+") or buildDir
  elseif projectConfig.settings.appPath then
    derivedDataPath = string.match(projectConfig.settings.appPath, "(.+/DerivedData/[^/]+)/.+")
  else
    derivedDataPath = require("xcodebuild.core.xcode").find_derived_data_path(
      projectConfig.settings.scheme,
      projectConfig.settings.workingDirectory
    )
  end

  if not derivedDataPath then
    notifications.send_error("Could not detect DerivedData. Please build project.")
    return
  end

  vim.defer_fn(function()
    local input = vim.fn.input("Delete " .. derivedDataPath .. "? (y/n) ", "")
    vim.cmd("echom ''")

    if input == "y" then
      notifications.send("Deleting: " .. derivedDataPath .. "...")

      -- TODO: should clean targets map?
      vim.fn.jobstart({ "rm", "-rf", derivedDataPath }, {
        on_exit = function(_, code)
          if code == 0 then
            notifications.send("Deleted: " .. derivedDataPath)
          else
            notifications.send_error("Failed to delete: " .. derivedDataPath)
          end
        end,
      })
    end
  end, 200)
end

---Builds the project for preview.
---@param callback function(code: number)|nil
---@see xcodebuild.core.xcode.build_project
function M.build_project_for_preview(callback)
  if not helpers.validate_project() then
    return
  end

  local xcode = require("xcodebuild.core.xcode")

  M.currentJobId = xcode.build_project({
    on_exit = function(_, code, _)
      util.call(callback, code)
    end,
    on_stdout = function() end,
    on_stderr = function() end,

    workingDirectory = projectConfig.settings.workingDirectory,
    destination = projectConfig.settings.destination,
    projectFile = projectConfig.settings.projectFile,
    scheme = projectConfig.settings.scheme,
    extraBuildArgs = config.commands.extra_build_args,
  })
end

return M
