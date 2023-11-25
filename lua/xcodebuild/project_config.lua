local M = {
  settings = {},
}

local function get_filepath()
  return vim.fn.getcwd() .. "/.nvim/xcodebuild/settings.json"
end

local function update_global_variables()
  vim.g.xcodebuild_device_name = M.settings.deviceName
  vim.g.xcodebuild_os = M.settings.os
  vim.g.xcodebuild_platform = M.settings.platform
  vim.g.xcodebuild_config = M.settings.config
  vim.g.xcodebuild_scheme = M.settings.scheme
end

function M.load_settings()
  local success, content = pcall(vim.fn.readfile, get_filepath())

  if success then
    M.settings = vim.fn.json_decode(content)
    update_global_variables()
  end
end

function M.save_settings()
  local json = vim.split(vim.fn.json_encode(M.settings), "\n", { plain = true })
  vim.fn.writefile(json, get_filepath())
  update_global_variables()
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
