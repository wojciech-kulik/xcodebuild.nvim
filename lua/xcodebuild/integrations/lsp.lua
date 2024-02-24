local M = {}

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

function M.quickfix_line()
  call_code_action(true)
end

function M.code_actions()
  call_code_action(false)
end

return M
