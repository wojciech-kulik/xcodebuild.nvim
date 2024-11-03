---@mod xcodebuild.broadcasting.notifications Notifications
---@tag xcodebuild.notifications
---@brief [[
---This module is responsible for sending notifications to the user.
---
---All notifications are sent via |xcodebuild.core.config.options.logs| functions:
---- `notify({message}, {severity})`
---- `notify_progress({message})`
---
---This way the user can customize the notifications and the progress bar.
---
---They can also be disabled or integrated with other plugins like `fidget.nvim`.
---
---@brief ]]

local config = require("xcodebuild.core.config").options.logs
local util = require("xcodebuild.util")

local M = {}

---@private
---@class BuildState
---@field id number|nil the id of the current build
---@field timer number|nil current timer id
---@field startTime number|nil the start time of the current build
---@field buildDuration number|nil the duration of the current build
local buildState = {}

local currentFrame = 0
local progressFrames = {
  "..........",
  " .........",
  "  ........",
  "   .......",
  "    ......",
  "     .....",
  "      ....",
  "       ...",
  "        ..",
  "         .",
  "          ",
  ".         ",
  "..        ",
  "...       ",
  "....      ",
  ".....     ",
  "......    ",
  ".......   ",
  "........  ",
  "......... ",
}

---@diagnostic disable-next-line: param-type-mismatch
math.randomseed(tonumber(tostring(os.time()):reverse():sub(1, 9)))

---Starts a timer to show the build progress.
---@param buildForTesting boolean if the build is for testing.
---@param expectedDuration number|nil the expected duration of the build in seconds. if nil, the progress bar will be spinning around without showing the expected duration.
---@return number # timer id
local function start_action_timer(buildForTesting, expectedDuration)
  local actionTitle = buildForTesting and "Building For Testing" or "Building"
  local startTime = os.time()
  local shouldShowProgressBar = require("xcodebuild.core.config").options.show_build_progress_bar

  local timer = vim.fn.timer_start(80, function()
    local duration = os.difftime(os.time(), startTime)

    if expectedDuration and shouldShowProgressBar then
      local progress
      local numberOfDots = math.floor(duration / expectedDuration * 10.0)
      local progressPercentage = math.min(100, math.floor(duration / expectedDuration * 100.0))
      require("xcodebuild.broadcasting.events").build_status(buildForTesting, progressPercentage, duration)

      if numberOfDots <= 10 then
        progress = string.rep(".", numberOfDots) .. string.rep(" ", 10 - numberOfDots)
      else
        progress = progressFrames[currentFrame % 20 + 1]
        currentFrame = currentFrame + 1
      end

      M.send_progress(string.format("[ %s ] %s (%d seconds)", progress, actionTitle, duration))
    else
      M.send_progress(string.format("%s [%d seconds]", actionTitle, duration))
      require("xcodebuild.broadcasting.events").build_status(buildForTesting, nil, duration)
    end
  end, { ["repeat"] = -1 })

  return timer
end

---Starts the build timer.
---@param buildForTesting boolean if the build is for testing.
---@return number # the id of the current build
function M.start_build_timer(buildForTesting)
  if buildState.timer then
    vim.fn.timer_stop(buildState.timer)
  end

  local projectConfig = require("xcodebuild.project.config")
  local lastBuildTime = projectConfig.settings.lastBuildTime

  buildState.id = math.random(10000000)
  buildState.timer = start_action_timer(buildForTesting or false, lastBuildTime)
  buildState.startTime = os.time()

  return buildState.id
end

---Stops the build timer if exists.
function M.stop_build_timer()
  if buildState.timer then
    buildState.buildDuration = os.difftime(os.time(), buildState.startTime)
    vim.fn.timer_stop(buildState.timer)
    buildState.timer = nil
  end
end

---Sends a message that the build is finished.
---@param report ParsedReport the build report.
---@param id number the id of the current build.
---@param isCancelled boolean if the build was cancelled.
---@param opts table|nil additional options.
---* {doNotShowSuccess} (boolean|nil)
---  if true, the success message will not be sent.
function M.send_build_finished(report, id, isCancelled, opts)
  opts = opts or {}

  if id ~= buildState.id then
    return
  end

  if buildState.timer then
    vim.fn.timer_stop(buildState.timer)
  end

  if isCancelled then
    M.send_warning("Build cancelled")
  elseif util.is_empty(report.buildErrors) then
    local duration = buildState.buildDuration
    local projectConfig = require("xcodebuild.project.config")
    projectConfig.settings.lastBuildTime = duration
    projectConfig.save_settings()

    if not opts.doNotShowSuccess then
      M.send(string.format("Build Succeeded [%d seconds]", duration))
    end
  else
    M.send_error("Build Failed [" .. #report.buildErrors .. " error(s)]")
  end

  buildState = {}
end

---Sends a message that tests have been started.
function M.send_tests_started()
  M.send("Starting Tests...")
end

---Sends a message that tests are in progress.
---Notifies about the progress of tests.
---@param report ParsedReport the test report.
function M.show_tests_progress(report)
  if not next(report.tests) then
    M.send_progress("Starting Tests...")
  else
    M.send_progress(
      "Running Tests [Executed: " .. report.testsCount .. ", Failed: " .. report.failedTestsCount .. "]"
    )
  end
end

---Sends a message that tests have been finished.
---Notifies also about the result of tests.
---@param report ParsedReport the test report.
---@param isCancelled boolean if tests were cancelled.
function M.send_tests_finished(report, isCancelled)
  if isCancelled then
    M.send_warning("Tests cancelled")
  elseif report.testsCount == 0 then
    M.send_error("Error: No Test Executed")
  else
    M.send(
      report.failedTestsCount == 0 and "All Tests Passed [Executed: " .. report.testsCount .. "]"
        or "Tests Failed [Executed: " .. report.testsCount .. ", Failed: " .. report.failedTestsCount .. "]",
      report.failedTestsCount == 0 and vim.log.levels.INFO or vim.log.levels.ERROR
    )
  end
end

---Sends the project settings.
---@param settings ProjectSettings the project settings.
function M.send_project_settings(settings)
  if settings.swiftPackage then
    M.send([[
      Project Configuration

      - platform: ]] .. settings.platform .. [[

      - workingDirectory: ]] .. (settings.workingDirectory or "-") .. [[

      - project: ]] .. settings.swiftPackage .. [[

      - scheme: ]] .. settings.scheme .. [[

      - device: ]] .. (settings.deviceName or settings.platform or "-") .. [[

      - osVersion: ]] .. (settings.os or "-") .. [[

      - destination: ]] .. settings.destination .. [[
    ]])
  else
    M.send([[
      Project Configuration

      - platform: ]] .. settings.platform .. [[

      - workingDirectory: ]] .. (settings.workingDirectory or "-") .. [[

      - project: ]] .. (settings.projectFile or "-") .. [[

      - xcodeproj: ]] .. (settings.xcodeproj or "-") .. [[

      - scheme: ]] .. settings.scheme .. [[

      - device: ]] .. (settings.deviceName or settings.platform or "-") .. [[

      - osVersion: ]] .. (settings.os or "-") .. [[

      - destination: ]] .. settings.destination .. [[

      - testPlan: ]] .. (settings.testPlan or "-") .. [[

      - bundleId: ]] .. (settings.bundleId or "-") .. [[

      - productName: ]] .. (settings.productName or "-") .. [[

      - appPath: ]] .. (settings.appPath or "-") .. [[
    ]])
  end
end

---Forwards the notification to the callback from the config.
---@param message string the message to send.
---@param severity number|nil the severity of the message.
---@see vim.log.levels
function M.send(message, severity)
  config.notify(message, severity)
end

---Forwards the notification to the callback from the config.
---@param message string the message to send.
function M.send_error(message)
  config.notify(message, vim.log.levels.ERROR)
end

---Forwards the notification to the callback from the config.
---@param message string the message to send.
function M.send_warning(message)
  config.notify(message, vim.log.levels.WARN)
end

---Forwards the notification to the callback from the config.
---@param message string the message to send.
function M.send_progress(message)
  config.notify_progress(message)
end

return M
