local M = {
  settings = {},
}

local function get_filepath()
  return vim.fn.getcwd() .. "/.nvim/xcodebuild/settings.json"
end

function M.load_settings()
  local success, content = pcall(vim.fn.readfile, get_filepath())

  if success then
    M.settings = vim.fn.json_decode(content)
  end
end

function M.save_settings()
  local json = vim.split(vim.fn.json_encode(M.settings), "\n", { plain = true })
  vim.fn.writefile(json, get_filepath())
end

function M.is_project_configured()
  local settings = M.settings
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
