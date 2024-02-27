---@mod xcodebuild.constants Constants
---@brief [[
---This module contains constants and type definitions that are
---used across the plugin.
---@brief ]]

local M = {}

---Platform type enum.
---These values match constants emitted by `xcodebuild` commands.
---@alias PlatformId
---| 'iOS' # physical iOS device (iPhone or iPad)
---| 'iOS Simulator' # iOS simulator (iPhone or iPad)
---| 'macOS' # macOS

---Platform constants.
---@class PlatformConstants
---@field IOS_PHYSICAL_DEVICE PlatformId physical iOS device (iPhone or iPad)
---@field IOS_SIMULATOR PlatformId iOS simulator (iPhone or iPad)
---@field MACOS PlatformId macOS

---Platform type enum.
---@type PlatformConstants
M.Platform = {
  IOS_PHYSICAL_DEVICE = "iOS",
  IOS_SIMULATOR = "iOS Simulator",
  MACOS = "macOS",
}

return M
