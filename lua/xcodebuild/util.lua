local M = {}

function M.is_empty(tab)
  return next(tab or {}) == nil
end

function M.is_not_empty(tab)
  return not M.is_empty(tab)
end

function M.get_buffers(opts)
  local result = {}

  for i, buf in ipairs(vim.api.nvim_list_bufs()) do
    if
      (opts or {}).returnNotLoaded == true and vim.api.nvim_buf_is_valid(buf)
      or vim.api.nvim_buf_is_loaded(buf)
    then
      result[i] = buf
    end
  end

  return result
end

function M.file_exists(name)
  local f = io.open(name, "r")

  if f ~= nil then
    io.close(f)
    return true
  end

  return false
end

function M.get_buf_by_name(name, opts)
  local allBuffers = M.get_buffers(opts)

  for _, buf in pairs(allBuffers) do
    if string.match(vim.api.nvim_buf_get_name(buf), ".*/([^/]*)$") == name then
      return buf
    end
  end

  return nil
end

function M.get_bufs_by_matching_name(pattern)
  local allBuffers = M.get_buffers()
  local result = {}

  for _, buf in pairs(allBuffers) do
    local bufName = vim.api.nvim_buf_get_name(buf)
    if string.find(bufName, pattern) then
      table.insert(result, { bufnr = buf, file = bufName })
    end
  end

  return result
end

function M.focus_buffer(bufNr)
  local _, window = next(vim.fn.win_findbuf(bufNr))
  if window then
    vim.api.nvim_set_current_win(window)
  end
end

function M.get_filename(filepath)
  return string.match(filepath, ".*%/([^/]*)%..+$")
end

function M.find_all_swift_files()
  local allFiles = M.shell("find '" .. vim.fn.getcwd() .. "' -type f -iname '*.swift' -not -path '*/.*'")
  local map = {}

  for _, filepath in ipairs(allFiles) do
    local filename = M.get_filename(filepath)
    if filename then
      map[filename] = filepath
    end
  end

  return map
end

function M.shell(cmd)
  local handle = io.popen(cmd)

  if handle ~= nil then
    local result = handle:read("*a")
    handle:close()
    return vim.split(result, "\n", { plain = true })
  end

  return {}
end

function M.merge_array(lhs, rhs)
  local result = lhs
  for _, val in ipairs(rhs) do
    table.insert(result, val)
  end

  return result
end

function M.trim(str)
  return string.match(str, "^%s*(.-)%s*$")
end

function M.select(tab, selector)
  local result = {}
  for _, value in ipairs(tab) do
    table.insert(result, selector(value))
  end

  return result
end

function M.filter(tab, predicate)
  local result = {}
  for _, value in ipairs(tab) do
    if predicate(value) then
      table.insert(result, value)
    end
  end

  return result
end

function M.has_suffix(text, suffix)
  return string.sub(text, -#suffix) == suffix
end

function M.has_prefix(text, prefix)
  return string.sub(text, 1, #prefix) == prefix
end

function M.contains(tab, val)
  for _, value in ipairs(tab) do
    if value == val then
      return true
    end
  end

  return false
end

function M.find(tab, predicate)
  for _, value in ipairs(tab) do
    if predicate(value) then
      return value
    end
  end

  return nil
end

function M.lsp_filepath_for_class_name(className)
  local lspResult, finished
  local bufnr = 0

  if vim.bo.filetype ~= "swift" then
    local sourcekitClients = vim.lsp.get_active_clients({ name = "sourcekit" })
    local sourcekitId = sourcekitClients[1] and sourcekitClients[1].id
    if sourcekitId then
      bufnr = vim.lsp.get_buffers_by_client_id(sourcekitId)[1] or 0
    end
  end

  vim.lsp.buf_request_all(bufnr, "workspace/symbol", { query = className }, function(result)
    finished = true
    lspResult = result
  end)

  local counter = 0
  while not finished and counter < 10 do
    vim.wait(10)
    counter = counter + 1
  end

  if lspResult and lspResult[1] and lspResult[1].result then
    for _, result in ipairs(lspResult[1].result) do
      if result.kind == 5 and result.name == className then
        return (result.location.uri:gsub("file://", ""))
      end
    end
  end

  return nil
end

return M
