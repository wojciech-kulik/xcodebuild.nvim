---@mod xcodebuild.core.previews UI Previews
---@tag xcodebuild.previews
---@brief [[
---This module contains the functionality to preview SwiftUI, UIKit, and AppKit views
---directly from Neovim.
---
---Installation:
--- - Make sure that your terminal supports images.
--- - Install the `snacks.nvim` plugin to enable image support.
--- - Make sure that `image` snack is enabled.
--- - Install Swift Package `wojciech-kulik/xcodebuild-nvim-preview` in your project.
--- - Configure the preview in a place that gets automatically called when the app starts.
---
---Examples:
---
---SwiftUI (supports hot reload):
--->swift
---    import SwiftUI
---    import XcodebuildNvimPreview
---
---    @main
---    struct MyApp: App {
---        var body: some Scene {
---            WindowGroup {
---                MainView()
---                  .setupNvimPreview { HomeView() }
---            }
---        }
---    }
---<
---
---UIKit (similar for AppKit):
--->swift
---    import XcodebuildNvimPreview
---
---    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
---        // ...
---
---        XcodebuildNvimPreview.setup(view: MainView())
---
---        // (optional) enable hot reload for preview (requires integration with `Inject`)
---        observeHotReload()
---            .sink { XcodebuildNvimPreview.setup(view: HomeView()) }
---            .store(in: &cancellables)
---
---        return true
---    }
---<
---
--- - Run `:XcodebuildPreviewGenerateAndShow` to generate and show the preview.
---   Alternatively, run `:XcodebuildPreviewGenerateAndShow hotReload` to keep
---   the app running for hot reloading.
---
---WARNING: snacks.nvim doesn't support clearing the in-memory cache right now, which makes it
---impossible to refresh previews without restarting Neovim. If you want to use this feature,
---you either need to wait until it is added (github.com/folke/snacks.nvim/issues/1394) or
---you can use my fork where I removed the cache: wojciech-kulik/snacks.nvim.
---
---If you want to use the hot reload feature, you need to integrate your app with `Inject`,
---read more about it here: https://github.com/wojciech-kulik/xcodebuild.nvim/wiki/Tips-&-Tricks#hot-reload
---@brief ]]

local config = require("xcodebuild.core.config").options.previews
local projectConfig = require("xcodebuild.project.config")
local projectBuilder = require("xcodebuild.project.builder")
local notifications = require("xcodebuild.broadcasting.notifications")
local xcode = require("xcodebuild.core.xcode")
local constants = require("xcodebuild.core.constants")
local util = require("xcodebuild.util")

local M = {}
local CANCELLED_CODE = 143

local function check_if_snacks_installed()
  local success, snacks = pcall(require, "snacks")

  if not success then
    notifications.send_error("The snacks.nvim plugin is required for this feature.")
    return false
  end

  if snacks.image.config.enabled == false then
    notifications.send_error("The image snack is not enabled. Please enable it in your snacks config.")
    return false
  end

  return true
end

local function validate()
  if not projectConfig.is_app_configured() then
    notifications.send_error("The project is missing some details. Please run XcodebuildSetup first.")
    return false
  end

  if constants.is_device(projectConfig.settings.platform) then
    notifications.send_error("Previews are not supported on physical devices.")
    return false
  end

  return check_if_snacks_installed()
end

---@return string the path to the preview image
local function getPath()
  local previewPath = "/tmp/xcodebuild.nvim"
  local productName = projectConfig.settings.productName
  return string.format("%s/%s.png", previewPath, productName)
end

---Shows notifications with the progress message.
---@param message string the message to show
local function update_progress(message)
  ---@diagnostic disable-next-line: inject-field
  vim.g.xcodebuild_last_status = message

  if config.show_notifications then
    notifications.send(message)
  end
end

---@param success boolean
local function show_result(success)
  if success then
    update_progress("Preview Updated")
  else
    update_progress("Failed to generate preview")
  end
end

local previewTimer = nil

local function stop_preview_timer()
  if previewTimer then
    vim.fn.timer_stop(previewTimer)
    previewTimer = nil
  end
end

---@param hotReload boolean|nil
---@param callback function|nil
local function wait_for_preview(hotReload, callback)
  local startTime = os.time()
  local device = require("xcodebuild.platform.device")

  previewTimer = vim.fn.timer_start(500, function()
    if util.file_exists(getPath()) then
      stop_preview_timer()
      show_result(true)
      util.call(callback)
      if not hotReload then
        device.kill_app()
      end
    elseif os.difftime(os.time(), startTime) > 30 then
      stop_preview_timer()
      show_result(false)
      device.kill_app()
    end
  end, { ["repeat"] = -1 })
end

---@param hotReload boolean|nil
---@param callback function|nil
local function generate_mobile_preview(hotReload, callback)
  local projectSettings = projectConfig.settings

  projectBuilder.build_project_for_preview(function(code)
    if code == CANCELLED_CODE then
      update_progress("Build Cancelled")
      return
    end

    if code ~= 0 then
      update_progress("Build Failed")
      return
    end

    xcode.install_app_on_simulator(projectSettings.destination, projectSettings.appPath, true, function()
      local command = {
        "xcrun",
        "simctl",
        "launch",
        "--terminate-running-process",
        "--console-pty",
        projectSettings.destination,
        projectSettings.bundleId,
        "--",
        "--xcodebuild-nvim-snapshot",
      }

      vim.fn.jobstart(command)
      wait_for_preview(hotReload, callback)
    end)
  end)
end

---@param hotReload boolean|nil
---@param callback function|nil
local function generate_macos_preview(hotReload, callback)
  local appPath = projectConfig.settings.appPath

  projectBuilder.build_project_for_preview(function(code)
    if code == CANCELLED_CODE then
      update_progress("Build Cancelled")
      return
    end

    if code ~= 0 then
      update_progress("Build Failed")
      return
    end

    vim.fn.jobstart({ "open", appPath, "--args", "--xcodebuild-nvim-snapshot" })
    wait_for_preview(hotReload, callback)
  end)
end

---Cancels awaiting preview generation.
function M.cancel()
  stop_preview_timer()
end

---Shows the preview image in a new window.
function M.show_preview()
  if not validate() then
    return
  end

  if not util.file_exists(getPath()) then
    update_progress("No preview available")
    return
  end

  local winid = vim.fn.bufwinid(getPath())
  if winid == -1 then
    vim.cmd(string.format(config.open_command, getPath()))
  end

  vim.defer_fn(function()
    local newWinid = vim.fn.bufwinid(getPath())
    if newWinid == -1 then
      return
    end

    vim.api.nvim_set_current_win(newWinid)
    vim.cmd("edit! | wincmd p")
  end, 500)
end

---Hides the preview window.
function M.hide_preview()
  if not validate() then
    return
  end

  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local name = vim.api.nvim_buf_get_name(buf)

    if name:match("/tmp/xcodebuild.nvim") then
      vim.api.nvim_win_close(win, true)
    end
  end
end

---Toggles the preview window.
function M.toggle_preview()
  if not validate() then
    return
  end

  if vim.fn.bufwinnr(getPath()) == -1 then
    M.show_preview()
  else
    M.hide_preview()
  end
end

---Builds & runs the project to generate a preview.
---If successful, the preview will be saved in `/tmp/xcodebuild.nvim/<product-name>.png`.
---If {hotReload} is true, the app will be kept running to allow hot reloading using `Inject`.
---The {callback} function is called after the preview is generated.
---@param hotReload boolean|nil
---@param callback function|nil
function M.generate_preview(hotReload, callback)
  if not validate() then
    return
  end

  local projectSettings = projectConfig.settings
  vim.fn.mkdir("/tmp/xcodebuild.nvim", "p")
  update_progress("Generating Preview...")

  vim.fn.delete(getPath())
  xcode.kill_app(projectSettings.productName, projectSettings.platform)

  local success, snacks = pcall(require, "snacks")
  if success and snacks.image.config.cache and snacks.image.config.cache ~= "" then
    vim.fn.delete(snacks.image.config.cache, "rf")
  end

  if projectSettings.platform == constants.Platform.MACOS then
    generate_macos_preview(hotReload, callback)
  else
    generate_mobile_preview(hotReload, callback)
  end
end

---Returns a list of actions with names for Previews.
---@return table<{name:string,action:function}>
function M.get_actions()
  return {
    { name = "Generate & Show Preview", action = require("xcodebuild.actions").previews_generate_and_show },
    { name = "Toggle Preview", action = M.toggle_preview },
  }
end

return M
