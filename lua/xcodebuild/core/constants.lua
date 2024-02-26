---@mod xcodebuild.constants Constants
---@brief [[
---This module contains constants and types definitions that are
---used across the plugin.
---@brief ]]

local M = {}

---Platform type enum.
---@alias PlatformId
---| 'iOS' # physical iOS device (iPhone or iPad)
---| 'iOS Simulator' # iOS simulator (iPhone or iPad)
---| 'macOS' # macOS

---Platform constants.
---@class Platform
---@field IOS_PHYSICAL_DEVICE PlatformId physical iOS device (iPhone or iPad)
---@field IOS_SIMULATOR PlatformId iOS simulator (iPhone or iPad)
---@field MACOS PlatformId macOS

---Platform type enum.
---This is returned by `xcodebuild` commands.
---@type Platform
M.Platform = {
  IOS_PHYSICAL_DEVICE = "iOS",
  IOS_SIMULATOR = "iOS Simulator",
  MACOS = "macOS",
}

return M
