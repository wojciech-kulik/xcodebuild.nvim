---@mod xcodebuild.integrations.lsp LSP Integration
---@brief [[
---This module is responsible for the integration with LSP.
---It provides functions, which fix issues with code actions in Swift.
---
---`sourcekit-lsp` requires from the provided range to match exactly the issue
---location. Neovim by default sends the current cursor position. Because of
---that, code actions won't appear unless you put the cursor in the right place.
---
---Functions from this module find the diagnostic for the current line and
---send the correct range to the LSP server.
---@brief ]]

local M = {}

---Calls code action for the current line.
---@param autofix boolean
local function call_code_action(autofix)
  local lineDiagnostic = vim.lsp.diagnostic.get_line_diagnostics()
  if not next(lineDiagnostic) then
    return vim.lsp.buf.code_action()
  end

  for _, diagnostic in ipairs(lineDiagnostic) do
    local start = { diagnostic.range.start.line + 1, diagnostic.range.start.character }
    return vim.lsp.buf.code_action({
      apply = autofix,
      range = { start = start, ["end"] = start },
    })
  end
end

---Calls code action for the current line.
---If one code action is available, it will apply the fix.
---If more than one code action is available, it will show the list.
---If no code action is available, nothing will happen.
function M.quickfix_line()
  call_code_action(true)
end

---Shows code actions for the current line.
---If no code action is available, nothing will happen.
function M.code_actions()
  call_code_action(false)
end

return M
