local notifications = require("xcodebuild.broadcasting.notifications")
local projectConfig = require("xcodebuild.project.config")
local xcode = require("xcodebuild.core.xcode")
local logsPanel = require("xcodebuild.xcode_logs.panel")
local config = require("xcodebuild.core.config").options
local events = require("xcodebuild.broadcasting.events")
local helpers = require("xcodebuild.helpers")
local deviceProxy = require("xcodebuild.platform.device_proxy")
local util = require("xcodebuild.util")

local M = {
  currentJobId = nil,
}

local function launch_app(waitForDebugger, callback)
  local settings = projectConfig.settings
  local function finished()
    notifications.send("Application has been launched")
    events.application_launched()
    util.call(callback)
  end

  notifications.send("Launching application...")

  if settings.platform == "macOS" then
    local path = settings.appPath .. "/Contents/MacOS/" .. settings.productName
    finished()
    return vim.fn.jobstart(path, { detach = true })
  end

  if settings.productName then
    M.kill_app()
  end

  if deviceProxy.should_use() then
    return deviceProxy.launch_app(settings.destination, settings.bundleId, finished)
  else
    return xcode.launch_app(
      settings.platform,
      settings.destination,
      settings.bundleId,
      waitForDebugger,
      finished
    )
  end
end

function M.kill_app(callback)
  if not helpers.validate_project() then
    return
  end

  local settings = projectConfig.settings
  if settings.platform == "macOS" then
    -- TODO: kill macOS process?
    return
  end

  if deviceProxy.is_installed() and settings.platform == "iOS" then
    M.currentJobId = deviceProxy.kill_app(settings.productName, callback)
  else
    M.currentJobId = xcode.kill_app(settings.productName, callback)
  end
end

function M.run_app(waitForDebugger, callback)
  if not helpers.validate_project() then
    return
  end

  if config.logs.auto_close_on_app_launch then
    logsPanel.close_logs()
  end

  if projectConfig.settings.platform == "macOS" then
    M.currentJobId = launch_app(waitForDebugger, callback)
  else
    M.currentJobId = M.install_app(function()
      M.currentJobId = launch_app(waitForDebugger, callback)
    end)
  end
end

function M.boot_simulator(callback)
  if not helpers.validate_project() then
    return
  end

  if projectConfig.settings.platform == "macOS" then
    notifications.send_error("Your selected device is macOS.")
    return
  end

  if projectConfig.settings.platform == "iOS" then
    notifications.send_error("Selected device cannot be booted. Please select a simulator.")
    return
  end

  notifications.send("Booting simulator...")
  xcode.boot_simulator(projectConfig.settings.destination, function()
    notifications.send("Simulator booted")
    util.call(callback)
  end)
end

function M.install_app(callback)
  if not helpers.validate_project() then
    return
  end

  local settings = projectConfig.settings
  if settings.platform == "macOS" then
    notifications.send_error("macOS apps cannot be installed")
    return
  end

  local function finished()
    notifications.send("Application has been installed")
    util.call(callback)
  end

  notifications.send("Installing application...")

  if deviceProxy.should_use() then
    return deviceProxy.install_app(settings.destination, settings.appPath, finished)
  else
    return xcode.install_app(settings.platform, settings.destination, settings.appPath, finished)
  end
end

function M.uninstall_app(callback)
  if not helpers.validate_project() then
    return
  end

  local settings = projectConfig.settings
  if settings.platform == "macOS" then
    notifications.send_error("macOS apps cannot be uninstalled")
    return
  end

  local function finished()
    notifications.send("Application has been uninstalled")
    util.call(callback)
  end

  notifications.send("Uninstalling application...")

  if deviceProxy.should_use() then
    M.currentJobId = deviceProxy.uninstall_app(settings.destination, settings.bundleId, finished)
  else
    M.currentJobId = xcode.uninstall_app(settings.platform, settings.destination, settings.bundleId, finished)
  end
end

return M
