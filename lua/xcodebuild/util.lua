---@mod xcodebuild.util Lua Utils
---@brief [[
---This module contains general lua helper functions used across the plugin.
---
---|xcodebuild.util| is for general language utils and |xcodebuild.helpers|
---are for plugin specific utils.
---@brief ]]

local M = {}

---Gets modified highlight without italic.
---@param name string
---@return table
function M.get_hl_without_italic(name)
  return M.get_modified_hl(name, { italic = false, default = true }) or { link = name, default = true }
end

---Read highlight and return the modified version.
---@param name string
---@param opts table
---@return table|nil # definition
function M.get_modified_hl(name, opts)
  local settings = vim.api.nvim_get_hl(0, { name = name })

  if M.is_empty(settings) then
    return nil
  end

  for k, v in pairs(opts) do
    settings[k] = v
  end

  return settings
end

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
---If {opts.returnNotLoaded} is true, it will
---return all buffers, including the ones that are not loaded.
---@param opts table|nil
---
---* {returnNotLoaded} (boolean)
---@return number[]
function M.get_buffers(opts)
  local result = {}

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if
      (opts or {}).returnNotLoaded == true and vim.api.nvim_buf_is_valid(buf)
      or vim.api.nvim_buf_is_loaded(buf)
    then
      table.insert(result, buf)
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

  for _, buf in ipairs(allBuffers) do
    if string.match(vim.api.nvim_buf_get_name(buf), ".*/([^/]*)$") == filename then
      return buf
    end
  end

  return nil
end

---Gets a buffer by its name.
---Returns also buffers that are not loaded.
---@param name string
---@return number|nil
function M.get_buf_by_name(name)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == name then
      return buf
    end
  end

  return nil
end

---Gets a buffer by its filetype.
---Returns also buffers that are not loaded.
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

  for _, buf in ipairs(allBuffers) do
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
---@param cmd string|string[]
---@return string[]
function M.shell(cmd)
  local result
  local jobid = vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data, _)
      result = data
    end,
  })
  vim.fn.jobwait({ jobid })

  return result or {}
end

---Runs a shell command asynchronously.
---@param cmd string|string[]
---@param callback function|nil
function M.shellAsync(cmd, callback)
  vim.fn.jobstart(cmd, {
    on_exit = callback,
  })
end

---Checks if fd is installed on the system.
---@return boolean
function M.is_fd_installed()
  return vim.fn.executable("fd") ~= 0
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

---Returns a new array without nil values.
---@param array any[]
---@return any[]
function M.skip_nil(array)
  local result = {}
  local maxIndex = 0

  for key, _ in pairs(array) do
    if type(key) == "number" and key > maxIndex then
      maxIndex = key
    end
  end

  if maxIndex == 0 then
    return result
  end

  for i = 1, maxIndex do
    if array[i] then
      table.insert(result, array[i])
    end
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

---Finds the index of a value that
---matches a predicate in an array.
---@param array any[]
---@param predicate fun(value: any): boolean
---@return number|nil
function M.indexOfPredicate(array, predicate)
  for i, v in ipairs(array) do
    if predicate(v) then
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
