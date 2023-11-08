local ui = require("xcodebuild.ui")
local util = require("xcodebuild.util")
local appdata = require("xcodebuild.appdata")
local config = require("xcodebuild.config").options.logs

local M = {}

local function insert_summary_header(output)
  table.insert(output, "-----------------------------")
  table.insert(output, "-- xcodebuild.nvim summary --")
  table.insert(output, "-----------------------------")
  table.insert(output, "")
end

local function split(filepath)
  local command = string.gsub(config.open_command, "{path}", filepath)
  vim.cmd(command)
end

local function get_buf_and_win_of_logs()
  local bufnr = util.get_buf_by_name(appdata.build_logs_filename, { returnNotLoaded = true })

  if bufnr then
    local winnr = vim.fn.win_findbuf(bufnr)
    if winnr then
      return bufnr, winnr[1]
    end
  end

  return bufnr, nil
end

local function format_logs(lines, callback)
  if config.only_summary then
    callback({})
  elseif config.logs_formatter then
    local logs_filepath = appdata.original_logs_filepath
    local command = "cat '" .. logs_filepath .. "' | " .. config.logs_formatter

    vim.fn.jobstart(command, {
      stdout_buffered = true,
      on_stdout = function(_, prettyOutput)
        callback(prettyOutput)
      end,
    })
  else
    callback(lines)
  end
end

local function refresh_logs_content()
  local bufnr, winnr = get_buf_and_win_of_logs()
  if not bufnr then
    return
  end

  vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
  vim.api.nvim_buf_set_option(bufnr, "readonly", false)

  if winnr then
    util.focus_buffer(bufnr)
    vim.cmd("silent e!")

    local linesNumber = #vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    vim.api.nvim_win_set_cursor(winnr, { linesNumber, 0 })

    if not config.auto_focus then
      vim.cmd("wincmd p")
    end
  end

  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
  vim.api.nvim_buf_set_option(bufnr, "readonly", true)
end

local function insert_test_results(report, prettyOutput)
  ui.print_tests_summary(report)

  if report.failedTestsCount > 0 then
    table.insert(prettyOutput, "Failing Tests:")
    for _, testsPerClass in pairs(report.tests) do
      for _, test in ipairs(testsPerClass) do
        if not test.success then
          local message = "    ✖ " .. test.class .. "." .. test.name
          if test.lineNumber then
            message = message .. ":" .. test.lineNumber
          end
          table.insert(prettyOutput, message)
        end
      end
    end
    table.insert(prettyOutput, "")
    table.insert(prettyOutput, "  ✖ " .. report.failedTestsCount .. " Test(s) Failed")
    table.insert(prettyOutput, "")
  else
    table.insert(prettyOutput, "  ✔ All Tests Passed [Executed: " .. report.testsCount .. "]")
    table.insert(prettyOutput, "")
  end
end

local function insert_warnings(prettyOutput, warnings)
  if util.is_empty(warnings) then
    return
  end

  table.insert(prettyOutput, "Warnings:")

  for _, warning in ipairs(warnings) do
    if warning.filepath then
      table.insert(
        prettyOutput,
        "   " .. warning.filepath .. ":" .. warning.lineNumber .. ":" .. (warning.columnNumber or 0)
      )
    end

    for index, message in ipairs(warning.message) do
      table.insert(
        prettyOutput,
        (index == 1 and not warning.filepath) and "   " .. message or "    " .. message
      )
    end
  end

  table.insert(prettyOutput, "")
end

local function insert_errors(prettyOutput, buildErrors)
  if util.is_empty(buildErrors) then
    return
  end

  table.insert(prettyOutput, "Errors:")

  for _, error in ipairs(buildErrors) do
    if error.filepath then
      table.insert(
        prettyOutput,
        "  ✖ " .. error.filepath .. ":" .. error.lineNumber .. ":" .. error.columnNumber
      )
    end

    for index, message in ipairs(error.message) do
      table.insert(
        prettyOutput,
        (index == 1 and not error.filepath) and "  ✖ " .. message or "    " .. message
      )
    end
  end
  table.insert(prettyOutput, "")
  table.insert(prettyOutput, "  ✖ Build Failed")
  table.insert(prettyOutput, "")
end

local function should_show_panel(report)
  local hasErrors = util.is_not_empty(report.buildErrors) or report.failedTestsCount > 0
  local configValue = util.is_not_empty(report.tests)
      and (hasErrors and config.auto_open_on_failed_tests or config.auto_open_on_success_tests)
    or (hasErrors and config.auto_open_on_failed_build or config.auto_open_on_success_build)

  return configValue
end

function M.notify(message, severity)
  config.notify(message, severity)
end

function M.notify_progress(message)
  config.notify_progress(message)
end

function M.set_logs(report, isTesting)
  appdata.write_original_logs(report.output)

  format_logs(report.output, function(prettyOutput)
    insert_summary_header(prettyOutput)

    if config.show_warnings then
      insert_warnings(prettyOutput, report.warnings)
    end

    if util.is_not_empty(report.buildErrors) then
      insert_errors(prettyOutput, report.buildErrors)
    elseif isTesting then
      insert_test_results(report, prettyOutput)
    else
      table.insert(prettyOutput, "  ✔ Build Succeeded")
      table.insert(prettyOutput, "")
    end

    appdata.write_build_logs(prettyOutput)

    if should_show_panel(report) then
      M.open_logs(true)
    end
    refresh_logs_content()
  end)
end

function M.open_logs(scrollToBottom)
  local logsFilepath = appdata.build_logs_filepath
  local bufnr, winnr = get_buf_and_win_of_logs()

  -- window is visible
  if winnr then
    if config.auto_focus then
      util.focus_buffer(bufnr)
    end
    return
  end

  split(logsFilepath)

  if scrollToBottom then -- new buffer should be scrolled
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    vim.api.nvim_win_set_cursor(0, { #lines, 0 })
  end

  if not config.auto_focus then
    vim.cmd("wincmd p")
  end
end

function M.close_logs()
  local _, winnr = get_buf_and_win_of_logs()

  if winnr then
    vim.api.nvim_win_close(winnr, true)
  end
end

function M.toggle_logs()
  local _, winnr = get_buf_and_win_of_logs()

  if winnr then
    M.close_logs()
  else
    M.open_logs(false)
  end
end

return M
