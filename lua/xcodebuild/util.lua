---@mod xcodebuild.util Lua Utils
---@brief [[
---This module contains general lua helper functions used across the plugin.
---
---|xcodebuild.util| is for general language utils and |xcodebuild.helpers|
---are for plugin specific utils.
---@brief ]]

local M = {}

---Creates a shallow copy of a table.
---If the table contains other tables, it will only copy the references.
---@param orig any
---@return any
function M.shallow_copy(orig)
  local orig_type = type(orig)
  local copy
  if orig_type == "table" then
    copy = {}
    for orig_key, orig_value in pairs(orig) do
      copy[orig_key] = orig_value
    end
  else -- number, string, boolean, etc
    copy = orig
  end
  return copy
end

---Checks if a table is empty or nil.
---@param table table|nil
---@return boolean
function M.is_empty(table)
  return next(table or {}) == nil
end

---Checks if a table is NOT empty and NOT nil.
---@param table table|nil
---@return boolean
function M.is_not_empty(table)
  return not M.is_empty(table)
end

---Gets all buffers in the current neovim instance.
---If `opts.returnNotLoaded` is true, it will
---return all buffers, including the ones that are not loaded.
---@param opts table|nil
---
---* {returnNotLoaded} (boolean)
---@return number[]
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

---Checks if a file exists.
---@param name string
---@return boolean
function M.file_exists(name)
  local f = io.open(name, "r")

  if f ~= nil then
    io.close(f)
    return true
  end

  return false
end

---Checks if a directory exists.
---@param path string
---@return boolean
function M.dir_exists(path)
  return vim.fn.isdirectory(path) ~= 0
end

---Gets a buffer by its filename.
---If `opts.returnNotLoaded` is true, it will
---return all buffers, including the ones that are not loaded.
---@param filename string
---@param opts table|nil
---* {returnNotLoaded} (boolean)
function M.get_buf_by_filename(filename, opts)
  local allBuffers = M.get_buffers(opts)

  for _, buf in pairs(allBuffers) do
    if string.match(vim.api.nvim_buf_get_name(buf), ".*/([^/]*)$") == filename then
      return buf
    end
  end

  return nil
end

---Gets a buffer by its name.
---@param name string
---@return number|nil
function M.get_buf_by_name(name)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.fn.bufname(buf) == name then
      return buf
    end
  end

  return nil
end

---Gets a buffer by its filetype.
---@param filetype string
---@return number|nil
function M.get_buf_by_filetype(filetype)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_option(buf, "filetype") == filetype then
      return buf
    end
  end

  return nil
end

---Gets all buffers that match a pattern.
---@param pattern string
---@return {bufnr: number, file: string}[]
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

---Focuses a buffer by its buffer number.
---If the buffer's window is not found, it will return false.
---@param bufnr number
---@return boolean
function M.focus_buffer(bufnr)
  local _, window = next(vim.fn.win_findbuf(bufnr))

  if window then
    vim.api.nvim_set_current_win(window)
    return true
  end

  return false
end

---Gets the filename from a filepath.
---@param filepath string
---@return string
function M.get_filename(filepath)
  return string.match(filepath, ".*%/([^/]*)%..+$")
end

---Runs a shell command and returns the output as a list of strings.
---@param cmd string
---@return string[]
function M.shell(cmd)
  local handle = io.popen(cmd)

  if handle ~= nil then
    local result = handle:read("*a")
    handle:close()
    return vim.split(result, "\n", { plain = true })
  end

  return {}
end

---Merges two arrays into a new one.
---@param lhs any[]
---@param rhs any[]
---@return any[]
function M.merge_array(lhs, rhs)
  local result = lhs
  for _, val in ipairs(rhs) do
    table.insert(result, val)
  end

  return result
end

---Trims whitespace from the beginning and end of a string.
---@param str string
---@return string
function M.trim(str)
  return string.match(str, "^%s*(.-)%s*$")
end

---Maps an array based on a {selector} function.
---@param tab any[]
---@param selector fun(value: any): any
---@return any[]
function M.select(tab, selector)
  local result = {}
  for _, value in ipairs(tab) do
    table.insert(result, selector(value))
  end

  return result
end

---Filters an array based on a {predicate} function.
---@param tab any[]
---@param predicate fun(value: any): boolean
---@return any[]
function M.filter(tab, predicate)
  local result = {}
  for _, value in ipairs(tab) do
    if predicate(value) then
      table.insert(result, value)
    end
  end

  return result
end

---Checks if a string ends with a suffix.
---@param text string
---@param suffix string
---@return boolean
function M.has_suffix(text, suffix)
  return string.sub(text, -#suffix) == suffix
end

---Checks if a string starts with a prefix.
---@param text string
---@param prefix string
---@return boolean
function M.has_prefix(text, prefix)
  return string.sub(text, 1, #prefix) == prefix
end

---Checks if an array contains a value.
---@param array any[]|nil
---@param value any
function M.contains(array, value)
  if not array then
    return false
  end

  for _, val in ipairs(array) do
    if val == value then
      return true
    end
  end

  return false
end

---Finds the first value in an array that matches a predicate.
---@param array any[]
---@param predicate fun(value: any): boolean
---@return any
function M.find(array, predicate)
  for _, value in ipairs(array) do
    if predicate(value) then
      return value
    end
  end

  return nil
end

---Calls {callback} with arguments if {callback} is not nil.
---Returns the result of the function call.
---@param callback function|nil
---@vararg any
---@return any
function M.call(callback, ...)
  if callback then
    return callback(...)
  end
end

---Finds the index of a value in an array.
---@param array any[]
---@param value any
---@return number|nil
function M.indexOf(array, value)
  for i, v in ipairs(array) do
    if v == value then
      return i
    end
  end

  return nil
end

---Reads file content and returns it as a list of lines.
---If the file does not exist, it will return false and an empty list.
---@param filepath string
---@return boolean, string[] # success: boolean, lines: string[]
function M.readfile(filepath)
  local handle = io.open(filepath, "r")
  if not handle then
    return false, {}
  end

  local content = handle:read("*a")
  local lines = vim.split(content, "\n", { plain = true })

  if #lines > 0 and lines[#lines] == "" then
    table.remove(lines, #lines)
  end

  handle:close()

  return true, lines
end

return M
