local config = require("xcodebuild.config").options.logs
local util = require("xcodebuild.util")

local M = {}

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

function M.start_action_timer(buildForTesting, expectedDuration)
  local actionTitle = buildForTesting and "Building For Testing" or "Building"
  local startTime = os.time()
  local shouldShowProgressBar = require("xcodebuild.config").options.show_build_progress_bar

  local timer = vim.fn.timer_start(80, function()
    local duration = os.difftime(os.time(), startTime)

    if expectedDuration and shouldShowProgressBar then
      local progress
      local numberOfDots = math.floor(duration / expectedDuration * 10.0)
      local progressPercentage = math.min(100, math.floor(duration / expectedDuration * 100.0))
      require("xcodebuild.events").build_status(buildForTesting, progressPercentage, duration)

      if numberOfDots <= 10 then
        progress = string.rep(".", numberOfDots) .. string.rep(" ", 10 - numberOfDots)
      else
        progress = progressFrames[currentFrame % 20 + 1]
        currentFrame = currentFrame + 1
      end

      M.send_progress(string.format("[ %s ] %s (%d seconds)", progress, actionTitle, duration))
    else
      M.send_progress(string.format("%s [%d seconds]", actionTitle, duration))
      require("xcodebuild.events").build_status(buildForTesting, nil, duration)
    end
  end, { ["repeat"] = -1 })

  return timer
end

function M.stop_build_timer()
  if buildState.timer then
    buildState.buildDuration = os.difftime(os.time(), buildState.startTime)
    vim.fn.timer_stop(buildState.timer)
    buildState.timer = nil
  end
end

function M.send_build_started(buildForTesting)
  if buildState.timer then
    vim.fn.timer_stop(buildState.timer)
  end

  local projectConfig = require("xcodebuild.project_config")
  local lastBuildTime = projectConfig.settings.lastBuildTime

  buildState.id = math.random(10000000)
  buildState.timer = M.start_action_timer(buildForTesting or false, lastBuildTime)
  buildState.startTime = os.time()

  return buildState.id
end

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
    local projectConfig = require("xcodebuild.project_config")
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

function M.send_tests_started()
  M.send("Starting Tests...")
end

function M.show_tests_progress(report)
  if not next(report.tests) then
    M.send_progress("Starting Tests...")
  else
    M.send_progress(
      "Running Tests [Executed: " .. report.testsCount .. ", Failed: " .. report.failedTestsCount .. "]"
    )
  end
end

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

function M.send_project_settings(settings)
  M.send([[
      Project Configuration

      - platform: ]] .. settings.platform .. [[

      - project: ]] .. settings.projectFile .. [[

      - xcodeproj: ]] .. (settings.xcodeproj or "-") .. [[

      - scheme: ]] .. settings.scheme .. [[

      - config: ]] .. settings.config .. [[

      - device: ]] .. (settings.deviceName or settings.platform or "-") .. [[

      - osVersion: ]] .. (settings.os or "-") .. [[

      - destination: ]] .. settings.destination .. [[

      - testPlan: ]] .. (settings.testPlan or "") .. [[

      - bundleId: ]] .. settings.bundleId .. [[

      - appPath: ]] .. settings.appPath .. [[

      - productName: ]] .. settings.productName .. [[
    ]])
end

function M.send(message, severity)
  config.notify(message, severity)
end

function M.send_error(message)
  config.notify(message, vim.log.levels.ERROR)
end

function M.send_warning(message)
  config.notify(message, vim.log.levels.WARN)
end

function M.send_progress(message)
  config.notify_progress(message)
end

return M
