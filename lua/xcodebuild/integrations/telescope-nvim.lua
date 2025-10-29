---@mod xcodebuild.integrations.telescope Telescope Picker
---@tag xcodebuild.pickers.telescope
---@brief [[
---This module is responsible for showing pickers using Telescope.nvim.
---
---@brief ]]

local util = require("xcodebuild.util")
local pickersUtils = require("xcodebuild.ui.pickers_utils")

local telescopePickers = require("telescope.pickers")
local telescopeFinders = require("telescope.finders")
local telescopeConfig = require("telescope.config").values
local telescopeActions = require("telescope.actions")
local telescopeState = require("telescope.actions.state")
local telescopeActionsUtils = require("telescope.actions.utils")

---@type PickerIntegration
local M = {
  start_progress = function() end,
  stop_progress = function() end,
  close = function() end,
  update_results = function() end,
  show = function() end,
  show_multiselect = function() end,
}

local activePicker = nil
local progressTimer = nil
local currentProgressFrame = 1
local progressFrames = {
  "[      ]",
  "[ .    ]",
  "[ ..   ]",
  "[ ...  ]",
  "[  ... ]",
  "[   .. ]",
  "[    . ]",
}

---Creates a picker entry.
---@param entry string|XcodeDevice|MacroError
---@return table
local function entry_maker(entry)
  local name

  if type(entry) == "table" then
    if entry.id then
      -- Device object
      ---@cast entry XcodeDevice
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

  return {
    value = entry,
    display = name,
    ordinal = name,
  }
end

---Updates the spinner animation.
local function update_telescope_spinner()
  if activePicker and vim.api.nvim_win_is_valid(activePicker.results_win) then
    currentProgressFrame = currentProgressFrame >= #progressFrames and 1 or currentProgressFrame + 1
    activePicker:set_prompt(progressFrames[currentProgressFrame] .. " ", true)
  else
    M.stop_progress()
  end
end

---Sets the picker actions for moving and deleting items.
---@param bufnr number
---@param opts PickerOptions|nil
local function set_picker_actions(bufnr, opts)
  local mappings = require("xcodebuild.core.config").options.device_picker.mappings
  local actionState = require("telescope.actions.state")
  local get_entries = function()
    if not activePicker then
      return {}
    end

    local entries = {}
    for entry in activePicker.manager:iter() do
      table.insert(entries, entry.value)
    end

    return entries
  end

  vim.keymap.set({ "n", "i" }, mappings.move_up_device, function()
    if actionState.get_current_line() ~= "" then
      return
    end

    local entries = get_entries()
    local currentEntry = actionState.get_selected_entry()
    if currentEntry then
      local index = currentEntry.index
      if index == 1 then
        return
      end

      pickersUtils.swap_entries(entries, index, index - 1)
      pickersUtils.reorder_device_in_cache(index, index - 1)
      M.update_results(entries)

      vim.defer_fn(function()
        if activePicker then
          activePicker:set_selection(index - 2)
        end
      end, 50)
    end
  end, { buffer = bufnr })

  vim.keymap.set({ "n", "i" }, mappings.move_down_device, function()
    if actionState.get_current_line() ~= "" then
      return
    end

    local entries = get_entries()
    local currentEntry = actionState.get_selected_entry()

    if currentEntry then
      local index = currentEntry.index
      if index == #entries then
        return
      end

      pickersUtils.swap_entries(entries, index, index + 1)
      pickersUtils.reorder_device_in_cache(index, index + 1)
      M.update_results(entries)

      vim.defer_fn(function()
        if activePicker then
          activePicker:set_selection(index)
        end
      end, 50)
    end
  end, { buffer = bufnr })

  vim.keymap.set({ "n", "i" }, mappings.delete_device, function()
    if activePicker and actionState.get_selected_entry() then
      activePicker:delete_selection(function(selection)
        pickersUtils.delete_device_from_cache(selection.value.id)
      end)
    end
  end, { buffer = bufnr })

  vim.keymap.set({ "n", "i" }, mappings.add_device, function()
    pickersUtils.add_device(opts)
  end, { buffer = bufnr })
end

---Sets up key bindings for the picker.
---@param prompt_bufnr number
---@param opts PickerOptions|nil
local function setup_bindings(prompt_bufnr, opts)
  opts = opts or {}

  if opts.on_refresh ~= nil then
    local mappings = require("xcodebuild.core.config").options.device_picker.mappings

    vim.keymap.set({ "n", "i" }, mappings.refresh_devices, function()
      opts.on_refresh()
    end, { silent = true, buffer = prompt_bufnr })
  end

  if opts.modifiable then
    set_picker_actions(prompt_bufnr, opts)
  end
end

---Starts the progress animation.
function M.start_progress()
  if not progressTimer then
    progressTimer = vim.fn.timer_start(80, update_telescope_spinner, { ["repeat"] = -1 })
  end
end

---Stops the progress animation.
function M.stop_progress()
  if progressTimer then
    vim.fn.timer_stop(progressTimer)
    progressTimer = nil
  end
end

---Updates the results of the picker and stops the animation.
---@param results any[]
function M.update_results(results)
  if activePicker then
    activePicker:refresh(
      telescopeFinders.new_table({
        results = results,
        entry_maker = entry_maker,
      }),
      {
        new_prefix = telescopeConfig.prompt_prefix,
      }
    )
    activePicker:reset_prompt()
  end
end

---Closes the active picker.
function M.close()
  if activePicker and util.is_not_empty(vim.fn.win_findbuf(activePicker.prompt_bufnr)) then
    telescopeActions.close(activePicker.prompt_bufnr)
  end
end

---Creates a previewer for macro objects.
---@return table
local function create_macro_previewer()
  local telescopePreviewers = require("telescope.previewers")
  local config = require("telescope.config").values

  return telescopePreviewers.new_buffer_previewer({
    title = "Macro Source Code",
    define_preview = function(self, entry)
      if type(entry.value) ~= "table" or not entry.value.targetName then
        return
      end

      local fallbackLines, sourceFiles = pickersUtils.get_macro_preview_content(entry.value)

      if not sourceFiles or #sourceFiles == 0 then
        vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, fallbackLines)
      else
        config.buffer_previewer_maker(sourceFiles[1], self.state.bufnr, {
          bufname = self.state.bufname,
          winid = self.state.winid,
          callback = function(bufnr)
            vim.bo[bufnr].filetype = "swift"
          end,
        })
      end
    end,
  })
end

---Shows a picker using Telescope.nvim.
---@param title string
---@param items any[]
---@param opts PickerOptions|nil
---@param callback fun(result: {index: number, value: any}, index: number)|nil
function M.show(title, items, opts, callback)
  opts = opts or {}

  local hasMacroItems = pickersUtils.is_macro_items(items)

  activePicker = telescopePickers.new(require("telescope.themes").get_dropdown({}), {
    prompt_title = title,
    finder = telescopeFinders.new_table({
      results = items,
      entry_maker = entry_maker,
    }),
    sorter = telescopeConfig.generic_sorter(),
    previewer = hasMacroItems and create_macro_previewer() or nil,
    file_ignore_patterns = {},
    attach_mappings = function(prompt_bufnr, _)
      setup_bindings(prompt_bufnr, opts)

      if hasMacroItems and opts.macro_approve_callback then
        local mapping = pickersUtils.get_macro_approval_mapping()

        vim.keymap.set({ "n", "i" }, mapping, function()
          local selection = telescopeState.get_selected_entry()
          if selection then
            -- Don't close picker - callback handles close and reopen
            opts.macro_approve_callback(selection)
          end
        end, { buffer = prompt_bufnr })
      end

      telescopeActions.select_default:replace(function()
        local selection = telescopeState.get_selected_entry()

        if opts.close_on_select and selection and selection.value ~= "[Reload Schemes]" then
          telescopeActions.close(prompt_bufnr)
        end

        if callback and selection then
          callback(selection, selection.index)
        end
      end)
      return true
    end,
  })

  activePicker:find()
end

---Shows a multiselect picker using Telescope.nvim.
---@param title string
---@param items any[]
---@param callback fun(result: any[])|nil
function M.show_multiselect(title, items, callback)
  activePicker = telescopePickers.new(require("telescope.themes").get_dropdown({}), {
    prompt_title = title,
    finder = telescopeFinders.new_table({
      results = items,
      entry_maker = entry_maker,
    }),
    sorter = telescopeConfig.generic_sorter(),
    file_ignore_patterns = {},
    attach_mappings = function(prompt_bufnr, _)
      telescopeActions.select_default:replace(function()
        local selection = telescopeState.get_selected_entry()
        local results = {}

        telescopeActionsUtils.map_selections(prompt_bufnr, function(entry)
          table.insert(results, entry.value)
        end)

        if util.is_empty(results) and selection then
          table.insert(results, selection.value)
        end

        if selection and selection.value ~= "[Reload Schemes]" then
          telescopeActions.close(prompt_bufnr)
        end

        if callback and selection then
          callback(results)
        end
      end)
      return true
    end,
  })

  activePicker:find()
end

return M
