local notifications = require("xcodebuild.notifications")
local util = require("xcodebuild.util")
local projectConfig = require("xcodebuild.project_config")
local xcode = require("xcodebuild.xcode")
local coordinator = require("xcodebuild.coordinator")

local M = {}

function M.build_and_run(callback)
  coordinator.build_and_run_app(callback)
end

function M.run_app(callback)
  coordinator.run_app(callback)
end

function M.wait_for_pid()
  local co = coroutine
  local productName = projectConfig.settings.productName

  if not productName then
    error("You must build the application first")
  end

  return co.create(function(dap_run_co)
    local pid = nil

    notifications.send("Attaching debugger...")
    for _ = 1, 10 do
      util.shell("sleep 1")
      pid = xcode.get_app_pid(productName)

      if tonumber(pid) then
        break
      end
    end

    if not tonumber(pid) then
      notifications.send_error("Launching the application timed out")
      co.close(dap_run_co)
    end

    co.resume(dap_run_co, pid)
  end)
end

return M
