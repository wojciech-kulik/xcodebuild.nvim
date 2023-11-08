local config = require("xcodebuild.config").options.logs

local M = {}

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

function M.show_tests_progress(report)
  if not next(report.tests) then
    M.send_progress("Building Project...")
  else
    M.send_progress(
      "Running Tests [Executed: " .. report.testsCount .. ", Failed: " .. report.failedTestsCount .. "]"
    )
  end
end

function M.print_tests_summary(report)
  if report.testsCount == 0 then
    M.send_error("Error: No Test Executed")
  else
    M.send(
      report.failedTestsCount == 0 and "All Tests Passed [Executed: " .. report.testsCount .. "]"
        or "Tests Failed [Executed: " .. report.testsCount .. ", Failed: " .. report.failedTestsCount .. "]",
      report.failedTestsCount == 0 and vim.log.levels.INFO or vim.log.levels.ERROR
    )
  end
end

function M.start_action_timer(actionTitle, expectedDuration)
  local startTime = os.time()
  local shouldShowProgressBar = require("xcodebuild.config").options.show_build_progress_bar

  local timer = vim.fn.timer_start(80, function()
    local duration = os.difftime(os.time(), startTime)

    if expectedDuration and shouldShowProgressBar then
      local progress
      local numberOfDots = math.floor(duration / expectedDuration * 10.0)

      if numberOfDots <= 10 then
        progress = string.rep(".", numberOfDots) .. string.rep(" ", 10 - numberOfDots)
      else
        progress = progressFrames[currentFrame % 20 + 1]
        currentFrame = currentFrame + 1
      end

      M.send_progress(string.format("[ %s ] %s (%d seconds)", progress, actionTitle, duration))
    else
      M.send_progress(string.format("%s [%d seconds]", actionTitle, duration))
    end
  end, { ["repeat"] = -1 })

  return timer
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
