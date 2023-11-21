local notifications = require("xcodebuild.notifications")
local util = require("xcodebuild.util")
local projectConfig = require("xcodebuild.project_config")
local xcode = require("xcodebuild.xcode")
local coordinator = require("xcodebuild.coordinator")

local M = {}

function M.build_and_debug(callback)
  local loadedDap, dap = pcall(require, "dap")
  if not loadedDap then
    error("Could not load dap plugin")
    return
  end

  xcode.kill_app(projectConfig.settings.productName)
  dap.continue()

  coordinator.build_project(false, function(report)
    local success = util.is_empty(report.buildErrors)

    if success then
      coordinator.run_app(false, callback)
    else
      dap.terminate()

      local loadedDapui, dapui = pcall(require, "dapui")
      if loadedDapui then
        dapui.close()
      end
    end
  end)
end

function M.debug_without_build(callback)
  local loadedDap, dap = pcall(require, "dap")
  if not loadedDap then
    error("Could not load dap plugin")
    return
  end

  xcode.kill_app(projectConfig.settings.productName)
  dap.continue()
  coordinator.run_app(false, callback)
end

function M.get_program_path()
  if projectConfig.settings.platform == "macOS" then
    return projectConfig.settings.appPath .. "/Contents/MacOS/" .. projectConfig.settings.productName
  else
    return projectConfig.settings.appPath
  end
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
