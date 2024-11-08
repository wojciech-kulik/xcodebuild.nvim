---@mod xcodebuild.project.config Project Configuration
---@brief [[
---This module is responsible for managing the project settings.
---
---Settings are saved in a JSON file located at `.nvim/xcodebuild/settings.json`.
---This way each project can have its own settings.
---It's important to open Neovim in the root directory of the project,
---so the settings can be loaded.
---@brief ]]

---@class ProjectSettings
---@field deviceName string|nil device name (ex. "iPhone 12")
---@field os string|nil OS version (ex. "14.5")
---@field platform PlatformId|nil platform (ex. "iOS")
---@field projectFile string|nil project file path (ex. "path/to/Project.xcodeproj")
---@field scheme string|nil scheme name (ex. "MyApp")
---@field destination string|nil destination (ex. "28B52DAA-BC2F-410B-A5BE-F485A3AFB0BC")
---@field bundleId string|nil bundle identifier (ex. "com.mycompany.myapp")
---@field appPath string|nil app path (ex. "path/to/MyApp.app")
---@field productName string|nil product name (ex. "MyApp")
---@field testPlan string|nil test plan name (ex. "MyAppTests")
---@field xcodeproj string|nil xcodeproj file path (ex. "path/to/Project.xcodeproj")
---@field swiftPackage string|nil Swift Package file path (ex. "path/to/Package.swift")
---@field workingDirectory string|nil parent directory of the project file
---@field lastBuildTime number|nil last build time in seconds
---@field showCoverage boolean|nil if the inline code coverage should be shown

local M = {}

---Current project settings.
---@type ProjectSettings
M.settings = {}

---Cached devices.
---@type XcodeDevice[]
M.cached_devices = {}

---Last platform used.
---@type PlatformId|nil
local last_platform = nil

local device_cache_filepath = vim.fn.getcwd() .. "/.nvim/xcodebuild/devices.json"

---Returns the filepath of the settings JSON file based on the
---current working directory.
local function get_filepath()
  return vim.fn.getcwd() .. "/.nvim/xcodebuild/settings.json"
end

---Updates the global variables with the current settings.
local function update_global_variables()
  ---@diagnostic disable: inject-field
  vim.g.xcodebuild_device_name = M.settings.deviceName
  vim.g.xcodebuild_os = M.settings.os
  vim.g.xcodebuild_platform = M.settings.platform
  vim.g.xcodebuild_scheme = M.settings.scheme
  vim.g.xcodebuild_test_plan = M.settings.testPlan
  ---@diagnostic enable: inject-field
end

---Loads the settings from the JSON file at `.nvim/xcodebuild/settings.json`.
---It also updates the global variables with the current settings.
function M.load_settings()
  local util = require("xcodebuild.util")
  local success, content = util.readfile(get_filepath())

  if success then
    M.settings = vim.fn.json_decode(content)
    last_platform = M.settings.platform
    update_global_variables()
  end
end

---Saves the settings to the JSON file at `.nvim/xcodebuild/settings.json`.
---It also updates the global variables with the current settings.
function M.save_settings()
  local json = vim.split(vim.fn.json_encode(M.settings), "\n", { plain = true })
  vim.fn.writefile(json, get_filepath())
  update_global_variables()
end

---Saves the device cache to the JSON file at `.nvim/xcodebuild/devices.json`.
function M.save_device_cache()
  local json = vim.split(vim.fn.json_encode(M.cached_devices), "\n", { plain = true })
  vim.fn.writefile(json, device_cache_filepath)
end

---Clears the device cache.
function M.clear_device_cache()
  M.cached_devices = {}
  M.save_device_cache()
end

---Loads the device cache from the JSON file at `.nvim/xcodebuild/devices.json`.
function M.load_device_cache()
  local util = require("xcodebuild.util")
  local success, content = util.readfile(device_cache_filepath)
  if success then
    M.cached_devices = vim.fn.json_decode(content)
  end
end

---Checks if SPM project is configured.
---@return boolean
function M.is_spm_configured()
  local settings = M.settings

  if
    settings.swiftPackage
    and settings.workingDirectory
    and settings.platform
    and settings.scheme
    and settings.destination
  then
    return true
  else
    return false
  end
end

---Checks if Xcode project is configured.
---@return boolean
function M.is_project_configured()
  local settings = M.settings
  if
    settings.platform
    and settings.projectFile
    and settings.scheme
    and settings.destination
    and settings.bundleId
    and settings.appPath
    and settings.productName
  then
    return true
  else
    return false
  end
end

---Checks if project is configured.
---@return boolean
function M.is_configured()
  return M.is_project_configured() or M.is_spm_configured()
end

---Updates the settings (`appPath`, `productName`, and `bundleId`) based on
---the current project.
---Calls `xcodebuild` commands to get the build settings.
---@param opts {skipIfSamePlatform:boolean} the options table
---@param callback function|nil the callback function to be called after
---the settings are updated.
function M.update_settings(opts, callback)
  local xcode = require("xcodebuild.core.xcode")
  local util = require("xcodebuild.util")

  if opts.skipIfSamePlatform and last_platform and last_platform == M.settings.platform then
    util.call(callback)
    return
  end

  if M.settings.swiftPackage then
    M.settings.appPath = nil
    M.settings.productName = nil
    M.settings.bundleId = nil
    last_platform = nil
    M.save_settings()
    util.call(callback)
  else
    local helpers = require("xcodebuild.helpers")
    local notifications = require("xcodebuild.broadcasting.notifications")

    helpers.defer_send("Updating project settings...")
    xcode.get_build_settings(
      M.settings.platform,
      M.settings.projectFile,
      M.settings.scheme,
      M.settings.xcodeproj,
      function(buildSettings)
        M.settings.appPath = buildSettings.appPath
        M.settings.productName = buildSettings.productName
        M.settings.bundleId = buildSettings.bundleId
        last_platform = M.settings.platform
        M.save_settings()
        util.call(callback)
        notifications.send("Project settings updated")
      end
    )
  end
end

---Sets the selected destination.
---@param destination XcodeDevice
function M.set_destination(destination)
  M.settings.destination = destination.id
  M.settings.platform = destination.platform
  M.settings.deviceName = destination.name
  M.settings.os = destination.os
  M.save_settings()
end

---Starts configuration wizard to set up the project settings.
function M.configure_project()
  local appdata = require("xcodebuild.project.appdata")
  local notifications = require("xcodebuild.broadcasting.notifications")

  appdata.create_app_dir()

  local pickers = require("xcodebuild.ui.pickers")
  local defer_print = function(text)
    vim.defer_fn(function()
      notifications.send(text)
    end, 100)
  end

  pickers.select_project(function()
    pickers.select_xcodeproj_if_needed(function()
      pickers.select_scheme(function()
        defer_print("Loading devices...")
        M.clear_device_cache()
        pickers.select_destination(function()
          if not require("xcodebuild.project.config").settings.swiftPackage then
            defer_print("Loading test plans...")
          end

          pickers.select_testplan(function()
            defer_print("Xcodebuild configuration has been saved!")
          end, { close_on_select = true, auto_select = true })

          M.update_settings({})
        end)
      end, { auto_select = true }) -- scheme
    end)
  end)
end

return M
