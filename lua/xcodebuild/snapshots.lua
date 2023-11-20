local util = require("xcodebuild.util")
local notifications = require("xcodebuild.notifications")
local appdata = require("xcodebuild.appdata")

local M = {}
local snapshotsDir = "/.nvim/xcodebuild/failing-snapshots"

function M.save_failing_snapshots(callback)
  local logs = appdata.read_original_logs()

  if util.is_empty(logs) then
    return
  end

  local xcresultPath
  for i = #logs, 1, -1 do
    xcresultPath = string.match(logs[i], "%s*(.*[^%.%/]+%.xcresult)")
    if xcresultPath then
      break
    end
  end

  if not xcresultPath then
    notifications.send_error("Could not locate xcresult file")
    return
  end

  local savePath = vim.fn.getcwd() .. snapshotsDir
  util.shell("mkdir -p '" .. savePath .. "'")

  local pathComponents = vim.split(debug.getinfo(1).source:sub(2), "/", { plain = true })
  local getsnapshotPath = table.concat(pathComponents, "/", 1, #pathComponents - 3) .. "/tools/getsnapshots"
  local command = getsnapshotPath .. " '" .. xcresultPath .. "' '" .. savePath .. "'"

  return vim.fn.jobstart(command, {
    on_exit = function(_, code)
      if code == 0 then
        if callback then
          callback()
        end
      else
        notifications.send_error(
          "Saving snapshots failed. Make sure that you have this file: " .. getsnapshotPath
        )
      end
    end,
  })
end

function M.get_failing_snapshots()
  local snapshotsPath = vim.fn.getcwd() .. snapshotsDir

  return util.filter(util.shell("find '" .. snapshotsPath .. "' -type f -iname '*.png'"), function(item)
    return item ~= ""
  end)
end

function M.delete_snapshots()
  local snapshotsPath = vim.fn.getcwd() .. snapshotsDir
  util.shell("rm -rf '" .. snapshotsPath .. "'")
end

return M
