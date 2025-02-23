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
--- - Configure the preview in `application(_:didFinishLaunchingWithOptions:)` function.
---   You can also try putting it somewhere else, but it must be triggered automatically
---   after the app launch without user interaction.
---
--->swift
---    import XcodebuildNvimPreview
---
---    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
---        // ...
---
---        XcodebuildNvimPreview.setup(view: MainView())
---
---        return true
---    }
---<
---
--- - Run `:XcodebuildPreviewGenerateAndShow` to generate and show the preview.
---
---WARNING: snacks.nvim doesn't support clearing the in-memory cache right now, which makes it
---impossible to refresh previews without restarting Neovim. If you want to use this feature,
---you either need to wait until it is added (github.com/folke/snacks.nvim/issues/1394) or
---you can use my fork where I removed the cache: wojciech-kulik/snacks.nvim.
---
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

---@param code number the exit code
local function handle_result(code)
  if code ~= 0 then
    update_progress("Failed to generate preview")
    return
  end

  update_progress("Preview Updated")
end

---@param callback function|nil
local function generate_mobile_preview(callback)
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

      vim.fn.jobstart(command, {
        on_exit = function(_, exitCode)
          handle_result(exitCode)
          if exitCode == 0 then
            util.call(callback)
          end
        end,
      })
    end)
  end)
end

---@param callback function|nil
local function generate_macos_preview(callback)
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

    vim.fn.jobstart({ "open", appPath, "-W", "--args", "--xcodebuild-nvim-snapshot" }, {
      on_exit = function(_, exitCode)
        handle_result(exitCode)
        if exitCode == 0 then
          util.call(callback)
        end
      end,
    })
  end)
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
    vim.api.nvim_win_call(newWinid, function()
      vim.cmd("edit!")
    end)
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
---The {callback} function is called after the preview is generated.
---@param callback function|nil
function M.generate_preview(callback)
  if not validate() then
    return
  end

  local projectSettings = projectConfig.settings
  vim.fn.mkdir("/tmp/xcodebuild.nvim", "p")
  update_progress("Generating Preview...")

  vim.fn.delete(getPath())
  xcode.kill_app(projectSettings.productName, projectSettings.platform)

  if projectSettings.platform == constants.Platform.MACOS then
    generate_macos_preview(callback)
  else
    generate_mobile_preview(callback)
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
