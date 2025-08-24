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
---@field show_multiselect fun(title: string, items: any[], callback?: fun(result: any[]))

local util = require("xcodebuild.util")
local constants = require("xcodebuild.core.constants")
local projectConfig = require("xcodebuild.project.config")

local M = {}

---Swaps two entries in a list.
---@param entries any[]
---@param index1 number
---@param index2 number
function M.swap_entries(entries, index1, index2)
  local tmp = entries[index1]
  entries[index1] = entries[index2]
  entries[index2] = tmp
end

---Shows the device addition picker.
---@param opts PickerOptions|nil
function M.add_device(opts)
  local pickers = require("xcodebuild.ui.pickers")

  pickers.select_destination(function()
    pickers.select_destination((opts or {}).device_select_callback, false, opts)
  end, true)
end

---Reorders a device in the cached devices list.
---@param oldIndex number
---@param newIndex number
function M.reorder_device_in_cache(oldIndex, newIndex)
  M.swap_entries(projectConfig.device_cache.devices, oldIndex, newIndex)
  projectConfig.save_device_cache()
end

---Deletes a device from the cached devices list by {deviceId}.
---@param deviceId string|nil
function M.delete_device_from_cache(deviceId)
  local index = util.indexOfPredicate(projectConfig.device_cache.devices, function(device)
    return device.id == deviceId
  end)

  if index then
    table.remove(projectConfig.device_cache.devices, index)
    projectConfig.save_device_cache()
  end
end

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
