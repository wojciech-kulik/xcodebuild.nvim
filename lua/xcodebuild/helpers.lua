local M = {}

local function cancel(source)
  if source.currentJobId then
    if vim.fn.jobstop(source.currentJobId) == 1 then
      require("xcodebuild.broadcasting.events").action_cancelled()
    end

    source.currentJobId = nil
  end
end

function M.cancel_actions()
  cancel(require("xcodebuild.platform.device"))
  cancel(require("xcodebuild.project.builder"))
  cancel(require("xcodebuild.tests.runner"))
end

function M.validate_project()
  local projectConfig = require("xcodebuild.project.config")
  local notifications = require("xcodebuild.broadcasting.notifications")

  if not projectConfig.is_project_configured() then
    notifications.send_error("The project is missing some details. Please run XcodebuildSetup first.")
    return false
  end

  return true
end

function M.before_new_run()
  local snapshots = require("xcodebuild.tests.snapshots")
  local testSearch = require("xcodebuild.tests.search")
  local logsParser = require("xcodebuild.xcode_logs.parser")
  local config = require("xcodebuild.core.config").options

  if config.auto_save then
    vim.cmd("silent wa!")
  end

  snapshots.delete_snapshots()
  logsParser.clear()
  testSearch.clear()
end

function M.find_all_swift_files()
  local util = require("xcodebuild.util")
  local allFiles =
    util.shell("find '" .. vim.fn.getcwd() .. "' -type f -iname '*.swift' -not -path '*/.*' 2>/dev/null")
  local map = {}

  for _, filepath in ipairs(allFiles) do
    local filename = util.get_filename(filepath)
    if filename then
      map[filename] = map[filename] or {}
      table.insert(map[filename], filepath)
    end
  end

  return map
end

return M
