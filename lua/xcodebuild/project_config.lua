local util = require("xcodebuild.util")

local M = {}
local settings = {}

local function get_file_path()
  local cwd = vim.fn.getcwd()
  local dirpath = cwd .. "/.nvim/xcodebuild"
  local filepath = dirpath .. "/settings.json"
  util.shell("mkdir -p '" .. dirpath .. "'")

  return filepath
end

function M.load_settings()
  local filepath = get_file_path()
  local success, content = pcall(vim.fn.readfile, filepath)

  if success then
    settings = vim.fn.json_decode(content)
  end
end

function M.save_settings()
  local filepath = get_file_path()
  local json = vim.split(vim.fn.json_encode(settings), "\n", { plain = true })
  vim.fn.writefile(json, filepath)
end

function M.settings()
  return settings
end

function M.is_project_configured()
  return settings.platform
    and settings.projectFile
    and settings.projectCommand
    and settings.scheme
    and settings.config
    and settings.destination
    and settings.bundleId
    and settings.appPath
    and settings.productName
end

return M
