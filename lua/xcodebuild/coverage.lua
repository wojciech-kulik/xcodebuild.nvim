local appdata = require("xcodebuild.appdata")
local util = require("xcodebuild.util")
local xcode = require("xcodebuild.xcode")
local projectConfig = require("xcodebuild.project_config")
local notifications = require("xcodebuild.notifications")
local config = require("xcodebuild.config").options.code_coverage

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
  vim.api.nvim_set_hl(0, "XcodebuildCoverageFull", { fg = "#50fa7b", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildCoverageNone", { fg = "#ff5555", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildCoveragePartial", { fg = "#f1fa8c", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildCoverageNotExecutable", { fg = "Gray", default = true })
end

function M.is_code_coverage_available()
  local archive = appdata.xcov_dir .. "/xccovarchive-0.xccovarchive"

  return util.dir_exists(archive)
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

  vim.api.nvim_exec_autocmds("User", {
    pattern = "XcodebuildCoverageToggled",
    data = projectConfig.settings.show_coverage,
  })
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
  local report_filepath = appdata.xcov_dir .. "/index.html"

  if not util.file_exists(report_filepath) then
    notifications.send_error("xcov report does not exist at " .. report_filepath)
    return
  end

  vim.fn.jobstart("open " .. report_filepath, {
    detach = true,
    on_exit = function() end,
  })
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

  util.shell("rm -rf '" .. appdata.xcov_dir .. "'")

  if util.shell("which xcov")[1] == "" then
    callback_if_set()
    notifications.send_error("xcov is not installed")
    return
  end

  local command = "xcov -"
    .. projectConfig.settings.projectCommand
    .. " --scheme '"
    .. projectConfig.settings.scheme
    .. "' --configuration '"
    .. projectConfig.settings.config
    .. "' --xccov_file_direct_path '"
    .. xcresultFilepath
    .. "' --output_directory '"
    .. appdata.xcov_dir
    .. "' 2>/dev/null"

  vim.fn.jobstart(command, {
    stdout_buffered = true,
    on_exit = callback_if_set,
  })
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

  local archive = appdata.xcov_dir .. "/xccovarchive-0.xccovarchive"

  xcode.get_code_coverage(archive, vim.api.nvim_buf_get_name(bufnr), function(lines)
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
        local mark

        if isPartial then
          mark = config.partially_covered
          isPartial = false
        elseif count == "*" then
          mark = config.covered
        elseif count == "0" then
          mark = config.not_covered
        else
          mark = config.not_executable
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
