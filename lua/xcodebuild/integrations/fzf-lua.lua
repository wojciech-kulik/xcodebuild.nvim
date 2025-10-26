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

  if type(entry) == "table" then
    if entry.id then
      -- Device object
      name = pickersUtils.get_destination_name(entry)
    elseif entry.targetName and entry.packageIdentity then
      -- Macro object
      name = string.format("%s (%s)", entry.targetName, entry.packageIdentity)
    else
      name = entry
    end
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

---Creates a preview function for macro objects.
---@param items any[]
---@return function|nil
local function create_macro_preview(items)
  if type(items[1]) ~= "table" or not items[1].targetName then
    return nil
  end

  return function(selected)
    -- Handle nil case (can happen during initialization)
    if not selected or not selected[1] then
      return ""
    end

    local selectedLine = selected[1]
    local macro = nil

    for _, item in ipairs(items) do
      if entry_maker(item) == selectedLine then
        macro = item
        break
      end
    end

    if not macro then
      return ""
    end

    local macros = require("xcodebuild.platform.macros")
    local files = macros.find_macro_source_files(macro.packageIdentity, macro.targetName)

    if not files or #files == 0 then
      local lines = {
        "⚠️  Macro source files not available",
        "",
        "Package: " .. macro.packageIdentity,
        "Target: " .. macro.targetName,
        "",
        "DerivedData not found or package not checked out.",
        "Try building the project first.",
      }

      if macro.message and macro.message ~= "" then
        table.insert(lines, "")
        table.insert(lines, "Error Message:")
        table.insert(
          lines,
          "─────────────────────────────────────"
        )
        for _, line in ipairs(vim.split(macro.message, "\n", { plain = true })) do
          table.insert(lines, line)
        end
      end

      return table.concat(lines, "\n")
    end

    -- Return a shell command to preview the file
    -- Use bat for syntax highlighting if available, otherwise use cat
    local filePath = vim.fn.shellescape(files[1])
    if vim.fn.executable("bat") == 1 then
      return "bat --color=always --style=numbers --language=swift " .. filePath
    else
      return "cat " .. filePath
    end
  end
end

---Shows a picker using fzf-lua.
---@param title string
---@param items any[]
---@param opts PickerOptions|nil
---@param callback fun(result: {index: number, value: any}, index: number)|nil
function M.show(title, items, opts, callback)
  opts = opts or {}

  local formattedItems = util.select(items, entry_maker)
  local hasMacroItems = type(items[1]) == "table" and items[1].targetName ~= nil

  pickerRequest = {
    title = title,
    items = items,
    formattedItems = formattedItems,
    opts = opts,
    multiselect = false,
    callback = callback,
  }

  ---@type table<string, fun(selected: string[]): nil>
  local actions = {
    ["default"] = function(selected)
      local index = util.indexOfPredicate(formattedItems, function(item)
        return item == selected[1]
      end)

      util.call(callback, { index = index, value = items[index] }, index)
    end,
  }

  if hasMacroItems and opts.macro_approve_callback then
    local pluginConfig = require("xcodebuild.core.config")
    local mappings = pluginConfig.options.macro_picker.mappings

    actions[map_shortcut(mappings.approve_macro)] = function(selected)
      local index = util.indexOfPredicate(formattedItems, function(item)
        return item == selected[1]
      end)

      opts.macro_approve_callback({ index = index, value = items[index] })
    end
  end

  set_bindings(actions, opts)

  local winopts = config.win_opts or {}
  winopts.title = title

  local previewFn = hasMacroItems and create_macro_preview(items) or nil
  local fzfOptions = {
    winopts = winopts,
    fzf_opts = config.fzf_opts or {},
    actions = actions,
  }

  if previewFn then
    fzfOptions.preview = {
      type = "cmd",
      fn = previewFn,
    }
  end

  fzf.fzf_exec(formattedItems, fzfOptions)
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
          for idx, item in ipairs(formattedItems) do
            if item == sel or item.name == sel then
              table.insert(result, items[idx])
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
