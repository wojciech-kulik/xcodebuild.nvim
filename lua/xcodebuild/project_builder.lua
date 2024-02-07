local notifications = require("xcodebuild.notifications")
local parser = require("xcodebuild.parser")
local util = require("xcodebuild.util")
local appdata = require("xcodebuild.appdata")
local quickfix = require("xcodebuild.quickfix")
local projectConfig = require("xcodebuild.project_config")
local xcode = require("xcodebuild.xcode")
local logs = require("xcodebuild.logs")
local config = require("xcodebuild.config").options
local events = require("xcodebuild.events")
local simulator = require("xcodebuild.simulator")
local helpers = require("xcodebuild.helpers")

local M = {}
local CANCELLED_CODE = 143

function M.build_and_run_app(waitForDebugger, callback)
  if not helpers.validate_project() then
    return
  end

  M.build_project({}, function(report)
    if util.is_not_empty(report.buildErrors) then
      notifications.send_error("Build Failed")
      logs.open_logs(true)
      return
    end

    simulator.run_app(waitForDebugger, callback)
  end)
end

function M.build_project(opts, callback)
  opts = opts or {}

  if not helpers.validate_project() then
    return
  end

  local buildId = notifications.send_build_started(opts.buildForTesting)
  helpers.before_new_run()

  local on_stdout = function(_, output)
    appdata.report = parser.parse_logs(output)
  end

  local on_exit = function(_, code, _)
    if code == CANCELLED_CODE then
      notifications.send_build_finished(appdata.report, buildId, true)
      events.build_finished(opts.buildForTesting or false, false, true, {})
      return
    end

    if config.restore_on_start then
      appdata.write_report(appdata.report)
    end

    quickfix.set(appdata.report)

    notifications.stop_build_timer()
    notifications.send_progress("Processing logs...")
    logs.set_logs(appdata.report, false, function()
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
    destination = projectConfig.settings.destination,
    projectCommand = projectConfig.settings.projectCommand,
    scheme = projectConfig.settings.scheme,
    config = projectConfig.settings.config,
    testPlan = projectConfig.settings.testPlan,
    extraBuildArgs = config.commands.extra_build_args,
  })
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

  vim.defer_fn(function()
    local input = vim.fn.input("Delete " .. derivedDataPath .. "? (y/n) ", "")
    vim.cmd("echom ''")

    if input == "y" then
      notifications.send("Deleting: " .. derivedDataPath .. "...")

      vim.fn.jobstart("rm -rf '" .. derivedDataPath .. "'", {
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

return M
