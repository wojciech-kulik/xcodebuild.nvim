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
  local lineDiagnostics = vim.lsp.diagnostic.get_line_diagnostics()
  if not next(lineDiagnostics) then
    return vim.lsp.buf.code_action()
  end

  local start = { lineDiagnostics[1].range.start.line + 1, lineDiagnostics[1].range.start.character }
  return vim.lsp.buf.code_action({
    apply = autofix,
    range = { start = start, ["end"] = start },
  })
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

---Restarts the `sourcekit-lsp` client.
function M.restart_sourcekit_lsp()
  local success, _ = pcall(require, "lspconfig")
  if not success then
    return
  end

  local clientId
  if vim.fn.has("nvim-0.10") == 1 then
    local client = vim.lsp.get_clients({ name = "sourcekit" })[1]
    clientId = client and client.name
  else
    ---@diagnostic disable-next-line: deprecated
    local client = vim.lsp.get_active_clients({ name = "sourcekit" })[1]
    clientId = client and client.id and tostring(client.id)
  end

  if not clientId then
    return
  end

  vim.cmd("LspRestart " .. clientId)
end

return M
