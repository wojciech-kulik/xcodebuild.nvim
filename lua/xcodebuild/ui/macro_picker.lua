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
---Supports multi-selection via tab key.
---@param macrosToApprove MacroError[]
function M.show_macro_approval_picker(macrosToApprove)
  if util.is_empty(macrosToApprove) then
    notifications.send("No unapproved macros found")
    return
  end

  -- Show security warning
  notifications.send_warning("⚠️  Only approve macros from trusted sources!")

  -- Callback when user selects macros
  local function on_select(selected)
    if util.is_empty(selected) then
      return
    end

    -- Selected items are the macro objects themselves
    local macros = require("xcodebuild.platform.macros")
    local success = macros.approve_macros(selected)

    if success then
      notifications.send("✓ Macros approved. Run build again to apply changes.")
    else
      notifications.send_error("Failed to approve macros")
    end
  end

  -- Pass macro objects directly - the picker integration will format them
  pickers.show_multiselect("Approve Swift Macros (Tab to select multiple)", macrosToApprove, on_select)
end

return M
