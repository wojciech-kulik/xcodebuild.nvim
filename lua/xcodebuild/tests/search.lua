local config = require("xcodebuild.core.config").options.test_search
local util = require("xcodebuild.util")
local xcode = require("xcodebuild.core.xcode")
local projectConfig = require("xcodebuild.project.config")
local helpers = require("xcodebuild.helpers")

local M = {
  targetsFilesMap = {},
}

local allSwiftFiles = {}
local classesCache = {}
local missingSymbols = {}

local LSPRESULT = {
  SUCCESS = 0,
  TIMEOUT = 1,
}

local function lsp_search(targetName, className)
  local sourcekitClients = vim.lsp.get_active_clients({ name = config.lsp_client })

  if util.is_empty(sourcekitClients) then
    vim.wait(30)
    return LSPRESULT.SUCCESS, nil
  end

  local lspResult, finished
  local bufnr = 0

  if vim.bo.filetype ~= "swift" then
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

  if lspResult and lspResult[1] and lspResult[1].result then
    for _, result in ipairs(lspResult[1].result) do
      if result.kind == 5 and result.name == className then
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

local function load_targets_map_if_needed()
  if util.is_empty(M.targetsFilesMap) then
    M.load_targets_map()
  end
end

function M.clear()
  allSwiftFiles = helpers.find_all_swift_files()
  classesCache = {}
  missingSymbols = {}
end

function M.load_targets_map()
  M.targetsFilesMap = xcode.get_targets_filemap(projectConfig.settings.appPath)
end

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

function M.get_test_key_for_file(file, class)
  if not class then
    return nil
  end

  if config.target_matching then
    local target = M.find_target_for_file(file)
    return M.get_test_key(target, class)
  end

  return class
end

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

return M
