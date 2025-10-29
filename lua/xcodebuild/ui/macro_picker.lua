---@mod xcodebuild.ui.macro_picker Macro Approval Picker
---@brief [[
---This module provides a picker UI for approving Swift macros.
---
---It shows a list of unapproved macros with their package information
---and allows multi-selection for batch approval.
---@brief ]]

local util = require("xcodebuild.util")
local notifications = require("xcodebuild.broadcasting.notifications")
local pickers = require("xcodebuild.ui.pickers")

local M = {}

---Shows a picker to approve Swift macros.
---@param macrosToApprove MacroError[]
---@param skipWarning boolean|nil
function M.show_macro_approval_picker(macrosToApprove, skipWarning)
  if util.is_empty(macrosToApprove) then
    notifications.send("No unapproved macros found")
    return
  end

  -- Show security warning only on first call (not on reopens)
  if not skipWarning then
    notifications.send_warning("⚠️  Only approve macros from trusted sources!")
  end

  -- Callback when user opens macro source (default action)
  local function on_open(selection)
    if not selection or not selection.value then
      return
    end

    -- Close picker first to avoid buffer modified issues
    pickers.close()

    -- Small delay to ensure picker is fully closed before opening file
    vim.defer_fn(function()
      local macros = require("xcodebuild.platform.macros")
      macros.open_macro_source(selection.value)
    end, 50)
  end

  -- Callback when user approves macro (custom action)
  local function on_approve(selection)
    if not selection or not selection.value then
      return
    end

    local macros = require("xcodebuild.platform.macros")
    local success = macros.approve_macros({ selection.value })

    if success then
      notifications.send("✓ Macro approved. Run build again to apply changes.")

      -- Close current picker and reopen with fresh data
      pickers.close()

      vim.defer_fn(function()
        local updatedMacros = macros.get_unapproved_macros()

        if util.is_empty(updatedMacros) then
          notifications.send("All macros approved!")
        else
          -- Reopen picker with remaining macros (skip warning on reopen)
          M.show_macro_approval_picker(updatedMacros, true)
        end
      end, 100)
    else
      notifications.send_error("Failed to approve macro")
    end
  end

  local config = require("xcodebuild.core.config")
  local mapping = config.options.macro_picker.mappings.approve_macro

  -- Pass macro objects directly - the picker integration will format them
  pickers.show(
    string.format("Swift Macros (<CR> to open, %s to approve)", mapping),
    macrosToApprove,
    on_open,
    { macro_approve_callback = on_approve }
  )
end

return M
