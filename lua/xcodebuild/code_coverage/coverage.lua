---@mod xcodebuild.code_coverage.coverage Code Coverage
---@tag xcodebuild.code-coverage
---@brief [[
---This module is responsible for showing the code coverage in the editor.
---@brief ]]

local util = require("xcodebuild.util")
local helpers = require("xcodebuild.helpers")
local xcode = require("xcodebuild.core.xcode")
local config = require("xcodebuild.core.config").options.code_coverage
local projectConfig = require("xcodebuild.project.config")
local appdata = require("xcodebuild.project.appdata")
local notifications = require("xcodebuild.broadcasting.notifications")
local events = require("xcodebuild.broadcasting.events")

local M = {}

local buffersWithCoverage = {}
local nsCovered = vim.api.nvim_create_namespace("xcodebuild-coverage-covered")
local nsNotCovered = vim.api.nvim_create_namespace("xcodebuild-coverage-not-covered")

---Jumps to the next or previous coverage sign.
---If `next` is `true`, jumps to the next sign, otherwise jumps to the previous sign.
---@param next boolean
local function jump_to_coverage(next)
  if not projectConfig.settings.showCoverage or not config.enabled then
    return
  end

  local cursorRow = vim.api.nvim_win_get_cursor(0)[1] - 1
  local marks = next and vim.api.nvim_buf_get_extmarks(0, nsNotCovered, { cursorRow + 1, 0 }, -1, {})
    or vim.api.nvim_buf_get_extmarks(0, nsNotCovered, 0, { cursorRow, 0 }, {})
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

---Sets up the code coverage signs and highlights.
function M.setup()
  vim.api.nvim_set_hl(0, "XcodebuildCoverageFullSign", util.get_hl_without_italic("DiagnosticOk"))
  vim.api.nvim_set_hl(0, "XcodebuildCoverageNoneSign", util.get_hl_without_italic("DiagnosticError"))
  vim.api.nvim_set_hl(0, "XcodebuildCoveragePartialSign", util.get_hl_without_italic("DiagnosticWarn"))
  vim.api.nvim_set_hl(0, "XcodebuildCoverageNotExecutableSign", { link = "Comment", default = true })
  -- XcodebuildCoverageFullNumber, XcodebuildCoveragePartialNumber
  -- XcodebuildCoverageNoneNumber, XcodebuildCoverageNotExecutableNumber
  -- XcodebuildCoverageFullLine, XcodebuildCoveragePartialLine
  -- XcodebuildCoverageNoneLine, XcodebuildCoverageNotExecutableLine
end

---Checks if the code coverage report is available.
---@return boolean
function M.is_code_coverage_available()
  local report = require("xcodebuild.code_coverage.report")

  return appdata.report.xcresultFilepath ~= nil
    and util.file_exists(appdata.report.xcresultFilepath)
    and report.is_report_available()
end

---Refreshes the code coverage for all buffers matching `file_pattern` from the config.
function M.refresh_all_buffers()
  for _, bufnr in ipairs(buffersWithCoverage) do
    vim.api.nvim_buf_clear_namespace(bufnr, nsNotCovered, 0, -1)
    vim.api.nvim_buf_clear_namespace(bufnr, nsCovered, 0, -1)
  end
  buffersWithCoverage = {}

  if not config.enabled or not projectConfig.settings.showCoverage then
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

---Jumps to the next coverage sign.
function M.jump_to_next_coverage()
  jump_to_coverage(true)
end

---Jumps to the previous coverage sign.
function M.jump_to_previous_coverage()
  jump_to_coverage(false)
end

---Exports the code coverage from the xcresult file.
---@param xcresultFilepath string
---@param callback function|nil
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

  util.shellAsync({ "rm", "-rf", appdata.coverage_report_filepath }, function()
    xcode.export_code_coverage_report(xcresultFilepath, appdata.coverage_report_filepath, callback_if_set)
  end)
end

---Toggles the code coverage visibility in all buffers.
---First, the code coverage must be exported using |export_coverage| function.
---@param isVisible boolean|nil
function M.toggle_code_coverage(isVisible)
  if not helpers.validate_project() then
    return
  elseif not config.enabled then
    notifications.send_error("Code coverage is disabled in xcodebuild.nvim config")
  elseif not M.is_code_coverage_available() then
    notifications.send_error(
      "Code coverage report does not exist. Make sure that you enabled code coverage for your test plan and run tests again."
    )
  end

  if isVisible ~= nil then
    projectConfig.settings.showCoverage = isVisible
  else
    projectConfig.settings.showCoverage = not projectConfig.settings.showCoverage
  end

  projectConfig.save_settings()
  M.refresh_all_buffers()
  notifications.send("Code Coverage: " .. (projectConfig.settings.showCoverage and "on" or "off"))

  events.toggled_code_coverage(projectConfig.settings.showCoverage)
end

---Shows the code coverage in the given buffer.
---First, the code coverage must be exported using |export_coverage| function.
---@param bufnr number
function M.show_coverage(bufnr)
  if
    not config.enabled
    or not projectConfig.settings.showCoverage
    or not vim.api.nvim_buf_is_loaded(bufnr)
    or vim.tbl_contains(buffersWithCoverage, bufnr)
    or not M.is_code_coverage_available()
  then
    return
  end

  vim.api.nvim_buf_clear_namespace(bufnr, nsCovered, 0, -1)
  vim.api.nvim_buf_clear_namespace(bufnr, nsNotCovered, 0, -1)
  table.insert(buffersWithCoverage, bufnr)

  xcode.get_code_coverage(appdata.report.xcresultFilepath, vim.api.nvim_buf_get_name(bufnr), function(lines)
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

        local namespace = nsCovered

        if isPartial then
          mark.sign_text = config.partially_covered_sign
          mark.sign_hl_group = "XcodebuildCoveragePartialSign"
          mark.number_hl_group = "XcodebuildCoveragePartialNumber"
          mark.line_hl_group = "XcodebuildCoveragePartialLine"
          isPartial = false
          namespace = nsNotCovered
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
          namespace = nsNotCovered
        else
          mark.sign_text = config.covered_sign
          mark.sign_hl_group = "XcodebuildCoverageFullSign"
          mark.number_hl_group = "XcodebuildCoverageFullNumber"
          mark.line_hl_group = "XcodebuildCoverageFullLine"
        end

        if mark.sign_text ~= "" then
          vim.api.nvim_buf_set_extmark(bufnr, namespace, tonumber(lineNumber) - 1, -1, mark)
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

---Shows the code coverage report in a floating window.
---First, the code coverage must be exported using |export_coverage| function.
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

  local coverageReport = require("xcodebuild.code_coverage.report")

  if not coverageReport.is_report_available() then
    notifications.send_error(
      "Code coverage report does not exist. Make sure that you enabled code coverage for your test plan and run tests again."
    )
  else
    coverageReport.open()
  end
end

return M
