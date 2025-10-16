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
function M.show_macro_approval_picker(macrosToApprove)
  if util.is_empty(macrosToApprove) then
    notifications.send("No unapproved macros found")
    return
  end

  -- Show security warning
  notifications.send_warning("⚠️  Only approve macros from trusted sources!")

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
    else
      notifications.send_error("Failed to approve macro")
    end
  end

  -- Pass macro objects directly - the picker integration will format them
  pickers.show(
    "Swift Macros (<CR> to open, <C-a> to approve)",
    macrosToApprove,
    on_open,
    { macro_approve_callback = on_approve }
  )
end

return M
