local appdata = require("xcodebuild.appdata")
local util = require("xcodebuild.util")
local xcode = require("xcodebuild.xcode")
local projectConfig = require("xcodebuild.project_config")
local notifications = require("xcodebuild.notifications")
local config = require("xcodebuild.config").options.code_coverage
local events = require("xcodebuild.events")

local M = {}

local buffersWithCoverage = {}
local ns = vim.api.nvim_create_namespace("xcodebuild-coverage")

local function validate_project()
  if not projectConfig.is_project_configured() then
    notifications.send_error("The project is missing some details. Please run XcodebuildSetup first.")
    return false
  end

  return true
end

local function jump_to_coverage(next)
  if not projectConfig.settings.show_coverage or not config.enabled then
    return
  end

  local cursorRow = vim.api.nvim_win_get_cursor(0)[1] - 1
  local marks = next and vim.api.nvim_buf_get_extmarks(0, ns, { cursorRow + 1, 0 }, -1, {})
    or vim.api.nvim_buf_get_extmarks(0, ns, 0, { cursorRow, 0 }, {})
  local lastRow = cursorRow

  if util.is_empty(marks) then
    return
  end

  table.sort(marks, function(a, b)
    if next then
      return a[2] < b[2]
    else
      return a[2] > b[2]
    end
  end)

  for _, mark in ipairs(marks) do
    local row = mark[2]
    if math.abs(row - lastRow) > 1 then
      vim.cmd(":" .. (row + 1))
      return
    else
      lastRow = row
    end
  end

  vim.cmd(":" .. (marks[#marks][2] + 1))
end

function M.setup()
  vim.api.nvim_set_hl(0, "XcodebuildCoverageFullSign", { link = "DiagnosticOk", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildCoverageNoneSign", { link = "DiagnosticError", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildCoveragePartialSign", { link = "DiagnosticWarn", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildCoverageNotExecutableSign", { link = "Comment", default = true })
  -- XcodebuildCoverageFullNumber, XcodebuildCoveragePartialNumber
  -- XcodebuildCoverageNoneNumber, XcodebuildCoverageNotExecutableNumber
  -- XcodebuildCoverageFullLine, XcodebuildCoveragePartialLine
  -- XcodebuildCoverageNoneLine, XcodebuildCoverageNotExecutableLine
end

function M.is_code_coverage_available()
  return util.dir_exists(appdata.coverage_filepath)
end

function M.toggle_code_coverage(isVisible)
  if not validate_project() then
    return
  elseif not config.enabled then
    notifications.send_error("Code coverage is disabled in xcodebuild.nvim config")
  elseif not M.is_code_coverage_available() then
    notifications.send_error(
      "Code coverage report does not exist. Make sure that you enabled code coverage for your test plan and run tests again."
    )
  end

  if isVisible ~= nil then
    projectConfig.settings.show_coverage = isVisible
  else
    projectConfig.settings.show_coverage = not projectConfig.settings.show_coverage
  end

  projectConfig.save_settings()
  M.refresh_all_buffers()
  notifications.send("Code Coverage: " .. (projectConfig.settings.show_coverage and "on" or "off"))

  events.toggled_code_coverage(projectConfig.settings.show_coverage)
end

function M.refresh_all_buffers()
  for _, bufnr in ipairs(buffersWithCoverage) do
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  end
  buffersWithCoverage = {}

  if not config.enabled or not projectConfig.settings.show_coverage then
    return
  end

  -- TODO: improve gsub - the conversion from wildcard to regex might not be reliable
  local filePattern = config.file_pattern
  local regexPattern = string.gsub(string.gsub(filePattern, "%.", "%%."), "%*", "%.%*")
  local buffers = util.get_bufs_by_matching_name(regexPattern) or {}

  for _, buffer in ipairs(buffers) do
    M.show_coverage(buffer.bufnr)
  end
end

function M.show_report()
  if not config.enabled then
    notifications.send_error("Code coverage is disabled in the config")
    return
  end

  local success, _ = pcall(require, "nui.tree")
  if not success then
    notifications.send_error(
      'nui.nvim is required to show code coverage report. Please add "MunifTanjim/nui.nvim" to dependencies of xcodebuild.nvim.'
    )
    return
  end

  local coverageReport = require("xcodebuild.coverage_report")

  if not coverageReport.is_report_available() then
    notifications.send_error(
      "Code coverage report does not exist. Make sure that you enabled code coverage for your test plan and run tests again."
    )
  else
    coverageReport.open()
  end
end

function M.export_coverage(xcresultFilepath, callback)
  local callback_if_set = function()
    if callback then
      callback()
    end
  end

  if not config.enabled then
    callback_if_set()
    return
  end

  util.shell("rm -rf '" .. appdata.coverage_filepath .. "'")
  util.shell("rm -rf '" .. appdata.coverage_report_filepath .. "'")

  xcode.export_code_coverage(xcresultFilepath, appdata.coverage_filepath, function()
    if util.dir_exists(appdata.coverage_filepath) then
      xcode.export_code_coverage_report(xcresultFilepath, appdata.coverage_report_filepath, callback_if_set)
    else
      callback_if_set()
    end
  end)
end

function M.jump_to_next_coverage()
  jump_to_coverage(true)
end

function M.jump_to_previous_coverage()
  jump_to_coverage(false)
end

function M.show_coverage(bufnr)
  if
    not config.enabled
    or not projectConfig.settings.show_coverage
    or not vim.api.nvim_buf_is_loaded(bufnr)
    or vim.tbl_contains(buffersWithCoverage, bufnr)
    or not M.is_code_coverage_available()
  then
    return
  end

  vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)
  table.insert(buffersWithCoverage, bufnr)

  xcode.get_code_coverage(appdata.coverage_filepath, vim.api.nvim_buf_get_name(bufnr), function(lines)
    local bracketsCounter = 0
    local isPartial = false
    local lineNumber, count

    for _, line in ipairs(lines) do
      local tempLineNumber, tempCount = string.match(line, "(%d+): ([%d%*]+)")
      if tempLineNumber and tempCount then
        lineNumber = tempLineNumber
        count = tempCount
      end

      local _, openBrackets = string.gsub(line, "%[", "")
      local _, closeBrackets = string.gsub(line, "%]", "")
      bracketsCounter = bracketsCounter + openBrackets - closeBrackets

      if bracketsCounter == 0 and lineNumber and count then
        local mark = {
          sign_text = "",
          sign_hl_group = "",
          number_hl_group = nil,
          line_hl_group = nil,
        }

        if isPartial then
          mark.sign_text = config.partially_covered_sign
          mark.sign_hl_group = "XcodebuildCoveragePartialSign"
          mark.number_hl_group = "XcodebuildCoveragePartialNumber"
          mark.line_hl_group = "XcodebuildCoveragePartialLine"
          isPartial = false
        elseif count == "*" then
          mark.sign_text = config.not_executable_sign
          mark.sign_hl_group = "XcodebuildCoverageNotExecutableSign"
          mark.number_hl_group = "XcodebuildCoverageNotExecutableNumber"
          mark.line_hl_group = "XcodebuildCoverageNotExecutableLine"
        elseif count == "0" then
          mark.sign_text = config.not_covered_sign
          mark.sign_hl_group = "XcodebuildCoverageNoneSign"
          mark.number_hl_group = "XcodebuildCoverageNoneNumber"
          mark.line_hl_group = "XcodebuildCoverageNoneLine"
        else
          mark.sign_text = config.covered_sign
          mark.sign_hl_group = "XcodebuildCoverageFullSign"
          mark.number_hl_group = "XcodebuildCoverageFullNumber"
          mark.line_hl_group = "XcodebuildCoverageFullLine"
        end

        if mark.sign_text ~= "" then
          vim.api.nvim_buf_set_extmark(bufnr, ns, tonumber(lineNumber) - 1, -1, mark)
        end

        lineNumber = nil
        count = nil
      elseif bracketsCounter > 0 then
        local col, length, executionCount = string.match(line, "%((%d+), (%d+), (%d+)%)")
        if col and length and executionCount then
          isPartial = isPartial or executionCount == "0"
        end
      end
    end
  end)
end

return M
