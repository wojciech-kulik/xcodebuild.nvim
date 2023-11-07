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

local function notify(message, severity)
  require("xcodebuild.logs").notify(message, severity)
end

local function notify_progress(message)
  require("xcodebuild.logs").notify_progress(message)
end

function M.show_tests_progress(report, firstChunk)
  if not next(report.tests) then
    if firstChunk then
      notify("Building Project...")
    end
  else
    notify_progress(
      "Running Tests [Executed: " .. report.testsCount .. ", Failed: " .. report.failedTestsCount .. "]"
    )
  end
end

function M.print_tests_summary(report)
  if report.testsCount == 0 then
    notify("Tests Failed [Executed: 0]", vim.log.levels.ERROR)
  else
    notify(
      report.failedTestsCount == 0 and "All Tests Passed [Executed: " .. report.testsCount .. "]"
        or "Tests Failed [Executed: " .. report.testsCount .. ", Failed: " .. report.failedTestsCount .. "]",
      report.failedTestsCount == 0 and vim.log.levels.INFO or vim.log.levels.ERROR
    )
  end
  vim.cmd("echo ''")
end

function M.open_test_file(tests)
  if not tests then
    return
  end

  local currentLine = vim.api.nvim_get_current_line()
  local testClass, testName, line = string.match(currentLine, "(%w*)%.(.*)%:(%d+)")

  for _, test in ipairs(tests[testClass] or {}) do
    if test.name == testName and test.filepath then
      vim.cmd("wincmd p | e " .. test.filepath .. " | " .. line)
      return
    end
  end
end

function M.start_action_timer(actionTitle, expectedDuration)
  local logs = require("xcodebuild.logs")
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

      logs.notify_progress(string.format("[ %s ] %s (%d seconds)", progress, actionTitle, duration))
    else
      logs.notify_progress(string.format("%s [%d seconds]", actionTitle, duration))
    end
  end, { ["repeat"] = -1 })

  return timer
end

return M
