---@mod xcodebuild.integrations.fzf-lua fzf-lua Integration
---@tag xcodebuild.pickers.fzf-lua
---@brief [[
---This module is responsible for showing pickers using fzf-lua.
---
---@brief ]]

local util = require("xcodebuild.util")
local pickersUtils = require("xcodebuild.ui.pickers_utils")
local config = require("xcodebuild.core.config").options.integrations.fzf_lua
local notifications = require("xcodebuild.broadcasting.notifications")
local fzf = require("fzf-lua")
local pickerRequest = {
  title = nil,
  items = {},
  formattedItems = {},
  opts = {},
  multiselect = false,
  callback = nil,
}

---@type PickerIntegration
local M = {
  start_progress = function() end,
  stop_progress = function() end,
  close = function() end,
  update_results = function() end,
  show = function() end,
  show_multiselect = function() end,
}

---Creates a picker entry.
---@param entry any
---@return string
local function entry_maker(entry)
  local name

  if type(entry) == "table" and entry.id then
    name = pickersUtils.get_destination_name(entry)
  else
    name = entry
  end

  return name
end

---Maps a shortcut from config to fzf-lua format.
---@param shortcut string
---@return string
local function map_shortcut(shortcut)
  -- stylua: ignore
  local result = shortcut
    :gsub("[<>]", "", 2)
    :gsub("[MmAa]%-", "alt-", 1)
    :gsub("[Cc]%-", "ctrl-", 1)
    :gsub("[Ss]%-", "shift-", 1)

  return result
end

---Sets the key bindings for the picker.
---@param actions table<string, function|table>
---@param opts PickerOptions
local function set_bindings(actions, opts)
  local mappings = require("xcodebuild.core.config").options.device_picker.mappings

  if opts.on_refresh and mappings.refresh_devices then
    actions[map_shortcut(mappings.refresh_devices)] = {
      opts.on_refresh,
      fzf.actions.resume,
    }
  end

  if not opts.modifiable then
    return
  end

  if mappings.add_device then
    actions[map_shortcut(mappings.add_device)] = {
      function()
        pickersUtils.add_device(opts)
      end,
      fzf.actions.resume,
    }
  end

  if mappings.delete_device then
    actions[map_shortcut(mappings.delete_device)] = {
      function(selected)
        local itemsIndex = util.indexOfPredicate(pickerRequest.formattedItems, function(item)
          return item == selected[1]
        end)

        pickersUtils.delete_device_from_cache(pickerRequest.items[itemsIndex].id)
        table.remove(pickerRequest.items, itemsIndex)

        M.show(pickerRequest.title, pickerRequest.items, opts, pickerRequest.callback)
      end,
      fzf.actions.resume,
    }
  end

  if mappings.move_up_device then
    actions[map_shortcut(mappings.move_up_device)] = {
      function()
        notifications.send_warning(
          "This feature is supported only by telescope.nvim and snacks.nvim. Please edit devices.json manually."
        )
      end,
      fzf.actions.resume,
    }
  end

  if mappings.move_down_device then
    actions[map_shortcut(mappings.move_down_device)] = {
      function()
        notifications.send_warning(
          "This feature is supported only by telescope.nvim and snacks.nvim. Please edit devices.json manually."
        )
      end,
      fzf.actions.resume,
    }
  end
end

---Starts the progress animation.
function M.start_progress()
  vim.api.nvim_win_set_config(0, { title = pickerRequest.title .. " (Loading...)" })
end

---Stops the progress animation.
function M.stop_progress()
  vim.api.nvim_win_set_config(0, { title = pickerRequest.title })
end

---Closes the active picker.
function M.close()
  if vim.bo.filetype == "fzf" then
    vim.cmd("silent! close!")
  end
end

---Updates the results of the picker and stops the animation.
---@param results any[]
function M.update_results(results)
  vim.defer_fn(function()
    if pickerRequest.multiselect then
      M.show_multiselect(pickerRequest.title, results, pickerRequest.callback)
    else
      M.show(pickerRequest.title, results, pickerRequest.opts, pickerRequest.callback)
    end
  end, 10)
end

---Shows a picker using fzf-lua.
---@param title string
---@param items any[]
---@param opts PickerOptions|nil
---@param callback fun(result: {index: number, value: any}, index: number)|nil
function M.show(title, items, opts, callback)
  opts = opts or {}

  local formattedItems = util.select(items, entry_maker)

  pickerRequest = {
    title = title,
    items = items,
    formattedItems = formattedItems,
    opts = opts,
    multiselect = false,
    callback = callback,
  }

  local actions = {
    ["default"] = function(selected)
      local index = util.indexOfPredicate(formattedItems, function(item)
        return item == selected[1]
      end)

      util.call(callback, { index = index, value = items[index] }, index)
    end,
  }

  set_bindings(actions, opts)

  local winopts = config.win_opts or {}
  winopts.title = title

  fzf.fzf_exec(formattedItems, {
    winopts = winopts,
    fzf_opts = config.fzf_opts or {},
    actions = actions,
  })
end

---Shows a multiselect picker using fzf-lua.
---@param title string
---@param items any[]
---@param callback fun(result: any[])|nil
function M.show_multiselect(title, items, callback)
  local formattedItems = util.select(items, entry_maker)

  pickerRequest = {
    title = title,
    items = items,
    formattedItems = formattedItems,
    opts = {},
    multiselect = true,
    callback = callback,
  }

  local fzf_opts = config.fzf_opts or {}
  fzf_opts["--multi"] = true

  local winopts = config.win_opts or {}
  winopts.title = title

  fzf.fzf_exec(formattedItems, {
    winopts = winopts,
    fzf_opts = fzf_opts,
    actions = {
      ["default"] = function(selected)
        local result = {}

        for _, sel in ipairs(selected) do
          for i, item in ipairs(formattedItems) do
            if item == sel or item.name == sel then
              table.insert(result, items[i])
              break
            end
          end
        end

        util.call(callback, result)
      end,
    },
  })
end

return M
