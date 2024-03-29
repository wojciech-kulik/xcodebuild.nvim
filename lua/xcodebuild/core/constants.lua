---@mod xcodebuild.constants Constants
---@brief [[
---This module contains constants and type definitions that are
---used across the plugin.
---@brief ]]

local M = {}

---@alias Buffer number
---@alias Row number

---Platform type enum.
---These values match constants emitted by `xcodebuild` commands.
---@alias PlatformId
---| 'iOS' # physical iOS device (iPhone or iPad)
---| 'iOS Simulator' # iOS simulator (iPhone or iPad)
---| 'tvOS Simulator' # tvOS simulator (Apple TV)
---| 'tvOS' # tvOS device (Apple TV)
---| 'watchOS Simulator' # watchOS simulator (Apple Watch)
---| 'watchOS' # watchOS device (Apple Watch)
---| 'visionOS Simulator' # visionOS simulator (Apple Glasses)
---| 'visionOS' # visionOS device (Apple Glasses)
---| 'macOS' # macOS

---Platform constants.
---@class PlatformConstants
---@field IOS_DEVICE PlatformId physical iOS device (iPhone or iPad)
---@field IOS_SIMULATOR PlatformId iOS simulator (iPhone or iPad)
---@field TVOS_SIMULATOR PlatformId tvOS simulator (Apple TV)
---@field TVOS_DEVICE PlatformId tvOS device (Apple TV)
---@field WATCHOS_SIMULATOR PlatformId watchOS simulator (Apple Watch)
---@field WATCHOS_DEVICE PlatformId watchOS device (Apple Watch)
---@field VISIONOS_SIMULATOR PlatformId visionOS simulator (Apple Glasses)
---@field VISIONOS_DEVICE PlatformId visionOS device (Apple Glasses)
---@field MACOS PlatformId macOS

---Platform type enum.
---@type PlatformConstants
M.Platform = {
  IOS_DEVICE = "iOS",
  IOS_SIMULATOR = "iOS Simulator",
  TVOS_SIMULATOR = "tvOS Simulator",
  TVOS_DEVICE = "tvOS",
  WATCHOS_SIMULATOR = "watchOS Simulator",
  WATCHOS_DEVICE = "watchOS",
  VISIONOS_SIMULATOR = "visionOS Simulator",
  VISIONOS_DEVICE = "visionOS",
  MACOS = "macOS",
}

---Returns the SDK name for the given platform.
---@param platform PlatformId
---@return string
function M.get_sdk(platform)
  if platform == M.Platform.IOS_DEVICE then
    return "iphoneos"
  elseif platform == M.Platform.IOS_SIMULATOR then
    return "iphonesimulator"
  elseif platform == M.Platform.TVOS_SIMULATOR then
    return "appletvsimulator"
  elseif platform == M.Platform.TVOS_DEVICE then
    return "appletvos"
  elseif platform == M.Platform.WATCHOS_SIMULATOR then
    return "watchsimulator"
  elseif platform == M.Platform.WATCHOS_DEVICE then
    return "watchos"
  elseif platform == M.Platform.VISIONOS_SIMULATOR then
    return "xrsimulator"
  elseif platform == M.Platform.VISIONOS_DEVICE then
    return "xros"
  elseif platform == M.Platform.MACOS then
    return "macosx"
  end

  assert(false, "Unknown platform: " .. platform)
  return ""
end

---Returns whether the given platform is a simulator.
---@param platform PlatformId
---@return boolean
function M.is_simulator(platform)
  return platform == M.Platform.IOS_SIMULATOR
    or platform == M.Platform.TVOS_SIMULATOR
    or platform == M.Platform.WATCHOS_SIMULATOR
    or platform == M.Platform.VISIONOS_SIMULATOR
end

---Returns whether the given platform is a device.
---Note: macOS is not considered a device.
---@param platform PlatformId
---@return boolean
function M.is_device(platform)
  return platform == M.Platform.IOS_DEVICE
    or platform == M.Platform.TVOS_DEVICE
    or platform == M.Platform.WATCHOS_DEVICE
    or platform == M.Platform.VISIONOS_DEVICE
end

return M
