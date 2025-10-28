---@mod xcodebuild.integrations.snacks-picker Snacks Picker Integration
---@tag xcodebuild.pickers.snacks
---@brief [[
---This module is responsible for showing pickers using Snacks.nvim.
---
---@brief ]]

local util = require("xcodebuild.util")
local pickersUtils = require("xcodebuild.ui.pickers_utils")
local snacks = require("snacks")
local config = require("xcodebuild.core.config").options.integrations.snacks_nvim

---@type PickerIntegration
local M = {
  start_progress = function() end,
  stop_progress = function() end,
  close = function() end,
  update_results = function() end,
  show = function() end,
  show_multiselect = function() end,
  show_snapshot_picker = function(_) end,
}

local pickerRequest = {
  title = "",
  ---@type snacks.Picker
  picker = nil,
  items = {},
  multiselect = false,
  opts = {},
  callback = nil,
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

---Moves the selected item up or down in the list.
---@param down boolean If true, move down; if false, move up.
local function move_item(down)
  local search = pickerRequest.picker.input.filter.pattern
  if not search or search ~= "" then
    -- Disable deletion when searching
    return
  end

  local selected = pickerRequest.picker:selected({ fallback = true })
  selected = selected and selected[1]

  if not selected then
    return
  end

  local index = util.indexOfPredicate(pickerRequest.picker.finder.items, function(it)
    return it.item.id == selected.item.id
  end)

  if not index then
    return
  end

  if (down and index == #pickerRequest.picker.finder.items) or (not down and index == 1) then
    return
  end

  local offset = down and 1 or -1

  pickersUtils.swap_entries(pickerRequest.picker.finder.items, index, index + offset)
  pickersUtils.swap_entries(pickerRequest.items, index, index + offset)
  pickersUtils.reorder_device_in_cache(index, index + offset)
  pickerRequest.picker:update({ force = true })
  pickerRequest.picker.list:view(index + offset)
end

---Sets the key bindings for the picker.
---@param keys table<string, any>
---@param opts PickerOptions
local function set_bindings(keys, opts)
  local mappings = require("xcodebuild.core.config").options.device_picker.mappings

  if opts.on_refresh then
    keys[mappings.refresh_devices] = {
      opts.on_refresh,
      mode = { "n", "i" },
    }
  end

  if not opts.modifiable then
    return
  end

  if mappings.add_device then
    keys[mappings.add_device] = {
      function()
        pickersUtils.add_device(opts)
      end,
      mode = { "n", "i" },
    }
  end

  if mappings.delete_device then
    keys[mappings.delete_device] = {
      function()
        local search = pickerRequest.picker.input.filter.pattern
        if not search or search ~= "" then
          -- Disable deletion when searching
          return
        end

        local selected = pickerRequest.picker:selected({ fallback = true })
        selected = selected and selected[1]

        if not selected then
          return
        end

        pickersUtils.delete_device_from_cache(selected.item.id)
        table.remove(pickerRequest.items, selected.idx)

        local listIndex = util.indexOfPredicate(pickerRequest.picker.finder.items, function(it)
          return it.item.id == selected.item.id
        end)
        table.remove(pickerRequest.picker.finder.items, listIndex)

        pickerRequest.picker:update({ force = true })
      end,
      mode = { "n", "i" },
    }
  end

  if mappings.move_down_device then
    keys[mappings.move_down_device] = {
      function()
        move_item(true)
      end,
      mode = { "n", "i" },
    }
  end

  if mappings.move_up_device then
    keys[mappings.move_up_device] = {
      function()
        move_item(false)
      end,
      mode = { "n", "i" },
    }
  end
end

---@class ShowOptions : PickerOptions
---@field preview function|nil

---@param title string
---@param items any[]
---@param opts ShowOptions|PickerOptions|nil
---@param multiselect boolean
---@param callback fun(result: {index: number, value: any}, index: number)|nil
local function _show(title, items, opts, multiselect, callback)
  opts = opts or {}

  local completed = false
  local hasMacroItems = pickersUtils.is_macro_items(items)

  pickerRequest = {
    title = title,
    items = items,
    opts = opts,
    multiselect = multiselect,
    callback = callback,
  }

  local finder_items = {}
  for idx, item in ipairs(items) do
    local text = entry_maker(item)
    table.insert(finder_items, {
      formatted = text,
      text = text,
      item = item,
      idx = idx,
    })
  end

  local keys = {}
  if not multiselect then
    keys["<Tab>"] = { "", mode = { "n", "i" } }
    keys["<S-Tab>"] = { "", mode = { "n", "i" } }
  end

  if hasMacroItems and opts.macro_approve_callback then
    local mapping = pickersUtils.get_macro_approval_mapping()

    keys[mapping] = {
      function()
        local selected = pickerRequest.picker:selected({ fallback = true })
        if selected and selected[1] and selected[1].item then
          pickerRequest.picker:close()
          opts.macro_approve_callback({ index = selected[1].idx, value = selected[1].item })
        end
      end,
      mode = { "n", "i" },
    }
  end

  set_bindings(keys, opts)

  local layout = config.layout
    or {
      preview = false,
      layout = {
        height = 0.4,
        width = 0.4,
      },
    }

  if opts.preview then
    layout.preview = true
  else
    layout.preview = false
  end

  local pickerOpts = {
    title = title,
    items = finder_items,
    format = snacks.picker.format.text,
    show_empty = true,
    layout = layout,
    actions = {
      confirm = function(picker, result)
        if completed then
          return
        end

        completed = true
        picker:close()

        if multiselect then
          local selected = picker:selected({ fallback = true })
          local multiResult = util.select(selected or {}, function(sel)
            return sel.item
          end)

          vim.schedule(function()
            util.call(callback, multiResult)
          end)
        else
          vim.schedule(function()
            util.call(callback, { index = result.idx, value = result.item }, result.idx)
          end)
        end
      end,
    },
    win = {
      input = {
        keys = keys,
      },
    },
  }

  if opts.preview then
    pickerOpts.preview = opts.preview
  end

  pickerRequest.picker = snacks.picker.pick(pickerOpts)
end

---Starts the progress animation.
function M.start_progress() end

---Stops the progress animation.
function M.stop_progress() end

---Closes the active picker.
function M.close()
  pickerRequest.picker:close()
end

---Creates a preview function for macro objects.
---@param items any[]
---@return function|nil
local function create_macro_preview(items)
  if not pickersUtils.is_macro_items(items) then
    return nil
  end

  ---@param ctx snacks.picker.preview.ctx
  return function(ctx)
    if not ctx or not ctx.item then
      return false
    end

    -- Handle both wrapped and direct item structures
    local macroItem = ctx.item.item or ctx.item

    -- Validate macro item has required fields
    if type(macroItem) ~= "table" or not macroItem.packageIdentity or not macroItem.targetName then
      ctx.preview:reset()
      ctx.preview:set_lines({
        "⚠️  Invalid macro item structure",
        "",
        "Missing packageIdentity or targetName",
      })
      return true
    end

    local fallbackLines, sourceFiles = pickersUtils.get_macro_preview_content(macroItem)

    if not sourceFiles or #sourceFiles == 0 then
      ctx.preview:reset()
      ctx.preview:set_lines(fallbackLines)
      return true
    end

    -- Read the Swift file and display it
    local filePath = sourceFiles[1]
    local ok, fileLines = pcall(vim.fn.readfile, filePath)

    if not ok or not fileLines then
      ctx.preview:reset()
      ctx.preview:notify("Could not read file: " .. filePath, "error")
      return false
    end

    ctx.preview:reset()
    ctx.preview:set_title(vim.fn.fnamemodify(filePath, ":t"))

    local buf = ctx.preview:scratch()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, fileLines)
    vim.bo[buf].filetype = "swift"

    return true
  end
end

---Updates the results of the picker and stops the animation.
---@param results any[]
function M.update_results(results)
  if pickerRequest.multiselect then
    M.show_multiselect(pickerRequest.title, results, pickerRequest.callback)
  else
    M.show(pickerRequest.title, results, pickerRequest.opts, pickerRequest.callback)
  end
end

---Shows a picker using Snacks.nvim.
---@param title string
---@param items any[]
---@param opts PickerOptions|nil
---@param callback fun(result: {index: number, value: any}, index: number)|nil
function M.show(title, items, opts, callback)
  opts = opts or {}
  local hasMacroItems = pickersUtils.is_macro_items(items)

  if hasMacroItems then
    local previewFn = create_macro_preview(items)
    if previewFn then
      ---@type ShowOptions
      local show_opts = vim.tbl_extend("force", opts, { preview = previewFn })
      _show(title, items, show_opts, false, callback)
      return
    end
  end

  _show(title, items, opts, false, callback)
end

---Shows a multiselect picker using Snacks.nvim.
---@param title string
---@param items any[]
---@param callback fun(result: any[])|nil
function M.show_multiselect(title, items, callback)
  _show(title, items, {}, true, callback)
end

--- Shows a file picker for failing snapshots with image preview.
---@param callback fun(result: {index: number, value: any}, index: number)|nil
function M.show_snapshot_picker(callback)
  local appData = require("xcodebuild.project.appdata")
  local notifications = require("xcodebuild.broadcasting.notifications")
  local path = appData.snapshots_dir

  if vim.fn.isdirectory(path) ~= 0 then
    snacks.picker.files({
      dirs = { path },
      confirm = function(_, result)
        vim.schedule(function()
          util.call(callback, { index = result.idx, value = result.item }, result.idx)
        end)
      end,
    })
  else
    notifications.send("No Failing Snapshots")
  end
end

return M
