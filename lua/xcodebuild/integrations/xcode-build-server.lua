---@mod xcodebuild.integrations.xcode-build-server xcode-build-server Integration
---@brief [[
---This module is responsible for the integration with xcode-build-server.
---
---See: https://github.com/SolaWing/xcode-build-server
---
---@brief ]]

local config = require("xcodebuild.core.config").options.integrations.xcode_build_server
local projectConfig = require("xcodebuild.project.config")

local M = {}

---Returns whether the xcode-build-server is installed.
---@return boolean
function M.is_installed()
  return vim.fn.executable("xcode-build-server") ~= 0
end

---Returns whether the integration is enabled.
---@return boolean
function M.is_enabled()
  return config.enabled
end

-- Toggles whether --skip-validate-bin flag is
-- passed to xcode-build-server's config command
-- and updates config if needed.
function M.toggle_bin_validation()
  if projectConfig.settings.validateBin == nil then
    projectConfig.settings.skipValidateBin = true
  else
    projectConfig.settings.skipValidateBin = not projectConfig.settings.skipValidateBin
  end

  projectConfig.save_settings()
  M.update_config()
end

---Updates xcode-build-server config if needed.
function M.update_config()
   if not M.is_enabled() or not M.is_installed() then
    return
  end

  local projectCommand = projectConfig.settings.projectCommand
  local scheme = projectConfig.settings.scheme

  if projectCommand and scheme then
    run_config(projectCommand, scheme)
  end
end

---Calls "config" command of xcode-build-server in order to update buildServer.json file.
---@param projectCommand string either "-project 'path/to/project.xcodeproj'" or "-workspace 'path/to/workspace.xcworkspace'"
---@param scheme string
---@return number # job id
function run_config(projectCommand, scheme)
  local cmd = "xcode-build-server config " .. projectCommand .. " -scheme '" .. scheme .. "'"

  if (projectConfig.settings.skipValidateBin or false) then
    cmd = cmd .. " --skip-validate-bin"
  end
  
  return vim.fn.jobstart(cmd, {
    on_exit = function()
      require("xcodebuild.integrations.lsp").restart_sourcekit_lsp()
    end,
  })
end

return M
