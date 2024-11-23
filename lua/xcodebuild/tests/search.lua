---@mod xcodebuild.tests.search Test Search
---@brief [[
---This module is responsible for providing test locations,
---target names, symbol file paths, and keys for hash maps.
---
---It uses LSP and file name matching to find results.
---@brief ]]

---0 - LSP request succeeded (doesn't mean that there is a match)
---1 - LSP request timed out
---@alias LSPResult number
---| 0 # success
---| 1 # timeout

local util = require("xcodebuild.util")
local helpers = require("xcodebuild.helpers")
local config = require("xcodebuild.core.config").options.test_search

local M = {}

---Hash map with all targets and their files.
---@type TargetMap
M.targetsFilesMap = {}

local allSwiftFiles = {}
local classesCache = {}
local missingSymbols = {}

---@type LSPResult
local LSPRESULT = {
  SUCCESS = 0,
  TIMEOUT = 1,
}

---Asks LSP to search for the {className} symbol.
---Then, it checks if the file is in the same {targetName}.
---
---If {targetName} is empty, it will return the first match.
---@param targetName string
---@param className string
---@return LSPResult
---@return string|nil # filepath
local function lsp_search(targetName, className)
  local sourcekitClients
  if vim.fn.has("nvim-0.10") == 1 then
    sourcekitClients = vim.lsp.get_clients({ name = config.lsp_client })
  else
    sourcekitClients = vim.lsp.get_active_clients({ name = config.lsp_client })
  end

  if util.is_empty(sourcekitClients) then
    vim.wait(30)
    return LSPRESULT.SUCCESS, nil
  end

  local lspResult, finished
  local bufnr = 0

  if vim.bo.filetype ~= "swift" then
    ---@diagnostic disable-next-line: undefined-field
    local sourcekitId = sourcekitClients[1].id
    bufnr = vim.lsp.get_buffers_by_client_id(sourcekitId)[1] or 0
  end

  vim.lsp.buf_request_all(bufnr, "workspace/symbol", { query = className }, function(result)
    finished = true
    lspResult = result
  end)

  local time = 0
  while not finished and time < config.lsp_timeout do
    vim.wait(10)
    time = time + 10
  end

  if time >= config.lsp_timeout then
    return LSPRESULT.TIMEOUT, nil
  end

  --- kind 5 - class, 23 - struct
  --- all types: https://github.com/swiftlang/sourcekit-lsp/blob/main/Sources/LanguageServerProtocol/SupportTypes/SymbolKind.swift
  if lspResult and lspResult[1] and lspResult[1].result then
    for _, result in ipairs(lspResult[1].result) do
      if (result.kind == 5 or result.kind == 23) and result.name == className then
        local filepath = (result.location.uri:gsub("file://", ""))

        if
          targetName == ""
          or not config.target_matching
          or M.find_target_for_file(filepath) == targetName
        then
          return LSPRESULT.SUCCESS, filepath
        end
      end
    end
  end

  return LSPRESULT.SUCCESS, nil
end

---Find the file using LSP.
---It uses cache to avoid multiple requests.
---@param targetName string
---@param className string
---@return string|nil # filepath
local function find_file_using_lsp(targetName, className)
  local key = (targetName or "") .. ":" .. className

  if classesCache[key] then
    return classesCache[key]
  end

  if missingSymbols[key] then
    return nil
  end

  local status, lspFile = lsp_search(targetName, className)

  if status == LSPRESULT.SUCCESS then
    classesCache[key] = lspFile
    missingSymbols[key] = not lspFile
  end

  return classesCache[key]
end

---Finds the file using file name matching assuming that
---the file name is the same as the class name.
---
---If {targetName} is empty, it will return the first match.
---@param targetName string
---@param className string
---@return string|nil # filepath
local function find_file_by_filename(targetName, className)
  local files = allSwiftFiles[className]
  if not files then
    return nil
  end

  for _, file in ipairs(files) do
    if targetName == "" or not config.target_matching or M.find_target_for_file(file) == targetName then
      return file
    end
  end
end

---Loads the targets map if it's empty.
---Sets `allSwiftFiles` with all swift files in the project.
local function load_targets_map_if_needed()
  if util.is_empty(M.targetsFilesMap) then
    M.load_targets_map()
  end
end

---Clears the LSP cache and the array with all Swift files.
---Doesn't clear the targets map (`M.targetsFilesMap`).
function M.clear()
  allSwiftFiles = helpers.find_all_swift_files()
  classesCache = {}
  missingSymbols = {}
end

---Loads the targets map based on the build folder.
---Sets `M.targetsFilesMap`.
function M.load_targets_map()
  local xcode = require("xcodebuild.core.xcode")
  local projectConfig = require("xcodebuild.project.config")

  if projectConfig.is_spm_configured() then
    local derivedDataPath = projectConfig.settings.buildDir
      or xcode.find_derived_data_path(projectConfig.settings.scheme, projectConfig.settings.workingDirectory)

    M.targetsFilesMap = derivedDataPath and xcode.get_targets_filemap(derivedDataPath) or {}
  else
    M.targetsFilesMap = xcode.get_targets_filemap(projectConfig.settings.appPath)
  end
end

---Returns the test key based on the {target} and {class}.
---Returns `Target:Class` or `:Class` if {target} is empty.
---It also can return only `Class` if target matching is
---disabled in config.
---@param target string|nil
---@param class string|nil
---@return string|nil
function M.get_test_key(target, class)
  if not class then
    return nil
  end

  if config.target_matching then
    return (target or "") .. ":" .. class
  else
    return class
  end
end

---The same as `get_test_key` but it uses the
---{filepath} to find the target first.
---@param filepath string
---@param class string|nil
---@return string|nil
function M.get_test_key_for_file(filepath, class)
  if not class then
    return nil
  end

  if config.target_matching then
    local target = M.find_target_for_file(filepath)
    return M.get_test_key(target, class)
  end

  return class
end

---Finds the target for {filepath} based on the map created
---from the build folder (`M.targetsFilesMap`).
---@param filepath string
---@return string|nil
function M.find_target_for_file(filepath)
  load_targets_map_if_needed()

  if util.is_empty(M.targetsFilesMap) then
    return nil
  end

  for target, files in pairs(M.targetsFilesMap) do
    if util.contains(files, filepath) then
      return target
    end
  end
end

---Finds the file path based on the {targetName} and {className}.
---It uses the configuration to decide the strategy,
---it could be LSP or filename matching, or both.
---@param targetName string
---@param className string
---@return string|nil # filepath
function M.find_filepath(targetName, className)
  local result

  -- initial LSP
  if vim.startswith(config.file_matching, "lsp") then
    result = find_file_using_lsp(targetName, className)
  end

  -- initial filename or filename fallback
  if
    (not result and config.file_matching == "lsp_filename")
    or vim.startswith(config.file_matching, "filename")
  then
    result = find_file_by_filename(targetName, className)
  end

  -- LSP fallback
  if not result and config.file_matching == "filename_lsp" then
    result = find_file_using_lsp(targetName, className)
  end

  return result
end

---Finds the file path based on the {filename}.
---@param filename string|nil
---@return string|nil # filepath
function M.find_filepath_by_filename(filename)
  if filename and not string.find(filename, "/") then
    for _, paths in pairs(M.targetsFilesMap) do
      for _, path in ipairs(paths) do
        if vim.endswith(path, filename) then
          return path
        end
      end
    end
  end

  return nil
end

return M
