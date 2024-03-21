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
---@field projectCommand string|nil project command (ex. "-project 'path/to/Project.xcodeproj'" or "-workspace 'path/to/Project.xcworkspace'")
---@field scheme string|nil scheme name (ex. "MyApp")
---@field destination string|nil destination (ex. "28B52DAA-BC2F-410B-A5BE-F485A3AFB0BC")
---@field bundleId string|nil bundle identifier (ex. "com.mycompany.myapp")
---@field appPath string|nil app path (ex. "path/to/MyApp.app")
---@field productName string|nil product name (ex. "MyApp")
---@field testPlan string|nil test plan name (ex. "MyAppTests")
---@field xcodeproj string|nil xcodeproj file path (ex. "path/to/Project.xcodeproj")
---@field lastBuildTime number|nil last build time in seconds
---@field showCoverage boolean|nil if the inline code coverage should be shown

local M = {}

---Current project settings.
---@type ProjectSettings
M.settings = {}

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

---Checks if the project is configured.
---@return boolean
function M.is_project_configured()
  local settings = M.settings
  if
    settings.platform
    and settings.projectFile
    and settings.projectCommand
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

---Updates the settings (`appPath`, `productName`, and `bundleId`) based on
---the current project.
---Calls `xcodebuild` commands to get the build settings.
---@param callback function|nil the callback function to be called after
---the settings are updated.
function M.update_settings(callback)
  local xcode = require("xcodebuild.core.xcode")
  xcode.get_build_settings(
    M.settings.platform,
    M.settings.projectCommand,
    M.settings.scheme,
    M.settings.xcodeproj,
    function(buildSettings)
      M.settings.appPath = buildSettings.appPath
      M.settings.productName = buildSettings.productName
      M.settings.bundleId = buildSettings.bundleId
      M.save_settings()
      if callback then
        callback()
      end
    end
  )
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
        pickers.select_destination(function()
          defer_print("Loading test plans...")
          pickers.select_testplan(function()
            defer_print("Xcodebuild configuration has been saved!")
          end, { close_on_select = true, auto_select = true })

          M.update_settings()
        end)
      end, { auto_select = true }) -- scheme
    end)
  end)
end

return M
