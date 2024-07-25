---@mod xcodebuild.xcode_logs.panel Logs Panel
---@tag xcodebuild.logs
---@brief [[
---This module contains the logs panel related functions.
---
---Key bindings:
--- - Press `o` on a failed test in the summary section to jump to the failing location
--- - Press `q` to close the panel
---
---@brief ]]

local util = require("xcodebuild.util")
local appdata = require("xcodebuild.project.appdata")
local config = require("xcodebuild.core.config").options.logs
local testSearch = require("xcodebuild.tests.search")
local events = require("xcodebuild.broadcasting.events")
local helpers = require("xcodebuild.helpers")

local M = {}

---Inserts summary header into the {output}.
---@param output string[]
local function insert_summary_header(output)
  table.insert(output, "-----------------------------")
  table.insert(output, "-- xcodebuild.nvim summary --")
  table.insert(output, "-----------------------------")
  table.insert(output, "")
end

---Uses `config.open_command` to show {filepath}.
---@param filepath string
---@see xcodebuild.config
local function split(filepath)
  local command = string.gsub(config.open_command, "{path}", filepath)
  vim.cmd(command)
end

---Returns buffer and window number of the logs buffer.
---@return number|nil, number|nil
local function get_buf_and_win_of_logs()
  local bufnr = util.get_buf_by_filename(appdata.build_logs_filename, { returnNotLoaded = true })

  if bufnr then
    local winnr = vim.fn.win_findbuf(bufnr)
    if winnr then
      return bufnr, winnr[1]
    end
  end

  return bufnr, nil
end

---Formats Xcode logs ({lines}) using `config.logs_formatter`.
-- Calls {callback} with the result.
---@param lines string[]
---@param callback fun(prettyOutput: string[])
local function format_logs(lines, callback)
  if config.only_summary then
    callback({})
  elseif config.logs_formatter and config.logs_formatter ~= "" then
    local logs_filepath = appdata.original_logs_filepath

    if config.logs_formatter:find("xcbeautify") and vim.fn.executable("xcbeautify") == 0 then
      callback(lines)
      return
    end

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

---Refreshes logs content.
local function refresh_logs_content()
  local bufnr, winnr = get_buf_and_win_of_logs()
  if not bufnr or not winnr then
    return
  end

  vim.api.nvim_win_call(winnr, function()
    vim.cmd("silent e!")
    vim.cmd("normal! G")
  end)

  if config.auto_focus then
    util.focus_buffer(bufnr)
  end
end

---Inserts test results into the {prettyOutput}.
---@param report ParsedReport
---@param prettyOutput string[]
local function insert_test_results(report, prettyOutput)
  if report.failedTestsCount > 0 then
    table.insert(prettyOutput, "Failing Tests:")
    for _, testsPerClass in pairs(report.tests) do
      for _, test in ipairs(testsPerClass) do
        if not test.success then
          local message = "    ✖ "
            .. (test.target and test.target .. "." or "")
            .. test.class
            .. "."
            .. test.name
          if test.lineNumber then
            message = message .. ":" .. test.lineNumber
          end
          table.insert(prettyOutput, message)
        end
      end
    end
    table.insert(prettyOutput, "")
    table.insert(prettyOutput, "  " .. report.failedTestsCount .. " Test(s) Failed")
    table.insert(prettyOutput, "")
  else
    table.insert(prettyOutput, "  ✔ All Tests Passed [Executed: " .. report.testsCount .. "]")
    table.insert(prettyOutput, "")
  end
end

---Inserts warnings into the {prettyOutput}.
---@param prettyOutput string[]
---@param warnings ParsedBuildWarning[]
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

---Inserts errors into the {prettyOutput}.
---@param prettyOutput string[]
---@param buildErrors ParsedBuildError[]
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
  table.insert(prettyOutput, "  Build Failed")
  table.insert(prettyOutput, "")
end

---Returns whether the panel should be shown based on the {report} and config.
---@param report ParsedReport
local function should_show_panel(report)
  local hasErrors = util.is_not_empty(report.buildErrors) or report.failedTestsCount > 0
  local configValue = util.is_not_empty(report.tests)
      and (hasErrors and config.auto_open_on_failed_tests or config.auto_open_on_success_tests)
    or (hasErrors and config.auto_open_on_failed_build or config.auto_open_on_success_build)

  return configValue
end

---Returns whether the panel should be closed based on the {report} and config.
---@param report ParsedReport
---@return boolean
local function should_close_panel(report)
  local isTesting = util.is_not_empty(report.tests)
  local hasErrors = util.is_not_empty(report.buildErrors)

  if not isTesting and not hasErrors and config.auto_close_on_success_build then
    return true
  else
    return false
  end
end

---Opens the test file or the test target in the previous window.
---@param tests table<string,ParsedTest[]>|nil
local function open_test_file(tests)
  if not tests then
    return
  end

  local currentLine = vim.api.nvim_get_current_line()
  local filepath, issueLine = string.match(currentLine, "[^/]*(/.+/[^/].+%.swift):?(%d*)")

  if filepath then
    vim.cmd("wincmd p | e " .. filepath .. " | " .. issueLine)
    return
  end

  local testTarget, testClass, testName, line = string.match(currentLine, "([%w_]*)%.?([%w_]*)%.(.*)%:(%d+)")
  local key = testSearch.get_test_key(testTarget, testClass)

  for _, test in ipairs(tests[key] or {}) do
    if test.name == testName and test.filepath then
      vim.cmd("wincmd p | e " .. test.filepath .. " | " .. line)
      return
    end
  end
end

---Clears the logs buffer.
function M.clear()
  local bufnr, _ = get_buf_and_win_of_logs()
  if not bufnr then
    return
  end

  helpers.update_readonly_buffer(bufnr, function()
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
  end)
end

---Appends {lines} to the logs buffer.
---@param lines string[]
---@param format boolean|nil default = true
function M.append_log_lines(lines, format)
  local bufnr, winnr = get_buf_and_win_of_logs()
  if not bufnr then
    return
  end

  if format == nil then
    format = true
  end

  if config.logs_formatter and config.logs_formatter ~= "" and format then
    if config.logs_formatter:find("xcbeautify") then
      if vim.fn.executable("xcbeautify") ~= 0 then
        lines = vim.fn.systemlist(config.logs_formatter, table.concat(lines, "\n"))
      end
    else
      lines = vim.fn.systemlist(config.logs_formatter, table.concat(lines, "\n"))
    end
  end

  helpers.update_readonly_buffer(bufnr, function()
    local currentBuf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, lines)

    if bufnr ~= currentBuf and winnr then
      vim.api.nvim_win_call(winnr, function()
        vim.cmd("normal! G")
      end)
    end
  end)
end

---Processes {report} and shows logs in the panel.
---It also writes the logs to the file.
---{callback} is called after the processing is finished.
---@param report ParsedReport
---@param isTesting boolean
---@param callback function
---@see xcodebuild.xcode_logs.parser.ParsedReport
function M.set_logs(report, isTesting, callback)
  appdata.write_original_logs(report.output)

  format_logs(report.output, function(prettyOutput)
    insert_summary_header(prettyOutput)

    if config.show_warnings then
      insert_warnings(prettyOutput, report.buildWarnings)
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
    elseif should_close_panel(report) then
      M.close_logs()
    end

    refresh_logs_content()
    util.call(callback)
  end)
end

---Opens the logs panel.
---@param scrollToBottom boolean
function M.open_logs(scrollToBottom)
  local logsFilepath = appdata.build_logs_filepath
  local bufnr, winnr = get_buf_and_win_of_logs()

  -- window is visible
  if winnr then
    if config.auto_focus and bufnr then
      util.focus_buffer(bufnr)
    end
    return
  end

  split(logsFilepath)
  events.toggled_logs(true, vim.api.nvim_win_get_buf(0), vim.api.nvim_get_current_win())

  if scrollToBottom then -- new buffer should be scrolled
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    vim.api.nvim_win_set_cursor(0, { #lines, 0 })
  end

  if not config.auto_focus and winnr == vim.api.nvim_get_current_win() then
    vim.cmd("wincmd p")
  end
end

---Closes the logs panel.
function M.close_logs()
  local _, winnr = get_buf_and_win_of_logs()

  if winnr then
    vim.api.nvim_win_close(winnr, true)
    events.toggled_logs(false, nil, nil)
  end
end

---Toggles the logs panel.
function M.toggle_logs()
  local _, winnr = get_buf_and_win_of_logs()

  if winnr then
    M.close_logs()
  else
    M.open_logs(false)
  end
end

---Sets up the logs buffer.
---@param bufnr number
function M.setup_buffer(bufnr)
  local win = vim.fn.win_findbuf(bufnr)

  if win and win[1] then
    vim.api.nvim_win_set_option(win[1], "wrap", false)
    vim.api.nvim_win_set_option(win[1], "spell", false)
  end

  helpers.nvim_buf_set_option_fwd_comp(bufnr, "modifiable", true)
  helpers.nvim_buf_set_option_fwd_comp(bufnr, "readonly", false)

  helpers.nvim_buf_set_option_fwd_comp(bufnr, "filetype", config.filetype)
  helpers.nvim_buf_set_option_fwd_comp(bufnr, "buflisted", false)
  helpers.nvim_buf_set_option_fwd_comp(bufnr, "fileencoding", "utf-8")
  helpers.nvim_buf_set_option_fwd_comp(bufnr, "modified", false)

  helpers.nvim_buf_set_option_fwd_comp(bufnr, "readonly", true)
  helpers.nvim_buf_set_option_fwd_comp(bufnr, "modifiable", false)

  vim.api.nvim_buf_set_keymap(bufnr, "n", "q", "<cmd>close<cr>", {})
  vim.api.nvim_buf_set_keymap(bufnr, "n", "o", "", {
    callback = function()
      open_test_file(appdata.report.tests)
    end,
    nowait = true,
  })
end

return M
