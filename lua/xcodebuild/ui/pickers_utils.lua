---@mod xcodebuild.ui.pickers_utils Utils For Pickers
---@tag xcodebuild.pickers_utils
---@brief [[
---This module is responsible for utility functions for pickers.
---
---@brief ]]

---@class PickerIntegration
---@field start_progress fun()
---@field stop_progress fun()
---@field close fun()
---@field update_results fun(results: any[])
---@field show fun(title: string, items: any[], opts?: PickerOptions, callback?: fun(result: {index: number, value: any}, index: number))
---@field show_multiselect fun(title: string, items: any[], opts?: PickerOptions, callback?: fun(result: any[]))

local util = require("xcodebuild.util")
local constants = require("xcodebuild.core.constants")

local M = {}

---Gets user-friendly device name
---@param destination XcodeDevice
---@return string
function M.get_destination_name(destination)
  local name = destination.name or ""
  local isDevice = constants.is_device(destination.platform)
  local isSimulator = constants.is_simulator(destination.platform)

  if destination.platform and isDevice then
    return util.trim(name) .. (destination.os and " (" .. destination.os .. ")" or "")
  end

  if destination.platform and not isSimulator then
    name = util.trim(name .. " " .. destination.platform)
  end
  if destination.platform == constants.Platform.MACOS and destination.arch then
    name = name .. " (" .. destination.arch .. ")"
  end
  if destination.os then
    name = name .. " (" .. destination.os .. ")"
  end
  if destination.variant then
    name = name .. " (" .. destination.variant .. ")"
  end
  if destination.error then
    name = name .. " [error]"
  end

  return name
end

return M
