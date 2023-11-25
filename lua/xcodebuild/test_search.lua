local config = require("xcodebuild.config").options.test_search
local util = require("xcodebuild.util")

local M = {}

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

  local find_target = require("xcodebuild.coordinator").find_target_for_file
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

  local counter = 0
  while not finished and counter < 10 do
    vim.wait(10)
    counter = counter + 1
  end

  if counter == 10 then
    return LSPRESULT.TIMEOUT, nil
  end

  if lspResult and lspResult[1] and lspResult[1].result then
    for _, result in ipairs(lspResult[1].result) do
      if result.kind == 5 and result.name == className then
        local filepath = (result.location.uri:gsub("file://", ""))

        if targetName == "" or not config.target_matching or find_target(filepath) == targetName then
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

  local find_target = require("xcodebuild.coordinator").find_target_for_file

  for _, file in ipairs(files) do
    if targetName == "" or not config.target_matching or find_target(file) == targetName then
      return file
    end
  end
end

function M.clear()
  allSwiftFiles = util.find_all_swift_files()
  classesCache = {}
  missingSymbols = {}
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
