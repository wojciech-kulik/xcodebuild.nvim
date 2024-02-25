---@mod xcodebuild.tests.snapshots Snapshot Tests
---@brief [[
---This module is responsible for saving and retrieving
---previews of failing snapshot tests.
---
---It uses the `getsnapshots` tool to create diffs.
---@brief ]]

local util = require("xcodebuild.util")
local appdata = require("xcodebuild.project.appdata")

local M = {}

---Extracts the failing snapshot tests from the provided
---{xcresultFilepath} and creates diff images in the
---`failing-snapshots` directory.
---
---It uses the external CLI tool located in `tools/getsnapshots`.
---@param xcresultFilepath string
---@param callback function|nil
function M.save_failing_snapshots(xcresultFilepath, callback)
  if not xcresultFilepath then
    util.call(callback)
    return
  end

  local savePath = appdata.snapshots_dir
  local getsnapshotPath = appdata.tool_path(GETSNAPSHOTS_TOOL)
  local command = getsnapshotPath .. " '" .. xcresultFilepath .. "' '" .. savePath .. "'"

  util.shell("mkdir -p '" .. savePath .. "'")

  return vim.fn.jobstart(command, {
    on_exit = function(_, code)
      if code == 0 then
        util.call(callback)
      else
        local notifications = require("xcodebuild.broadcasting.notifications")
        notifications.send_error(
          "Saving snapshots failed. Make sure that you have this file: " .. getsnapshotPath
        )
      end
    end,
  })
end

---Returns a list of sorted file paths with snapshot diffs.
---@return string[]
function M.get_failing_snapshots()
  local snapshots = util.filter(
    util.shell("find '" .. appdata.snapshots_dir .. "' -type f -iname '*.png' 2>/dev/null"),
    function(item)
      return item ~= ""
    end
  )

  table.sort(snapshots, function(a, b)
    return a < b
  end)

  return snapshots
end

---Deletes the `failing-snapshots` directory.
function M.delete_snapshots()
  util.shell("rm -rf '" .. appdata.snapshots_dir .. "'")
end

return M
