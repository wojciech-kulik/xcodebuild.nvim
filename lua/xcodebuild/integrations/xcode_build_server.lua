---@mod xcodebuild.integrations.xcode_build_server xcode-build-server Integration
---@brief [[
---This module is responsible for the integration with xcode-build-server.
---
---See: https://github.com/SolaWing/xcode-build-server
---
---@brief ]]

local config = require("xcodebuild.core.config").options.integrations.xcode_build_server

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

---Calls "config" command of xcode-build-server in order to update buildServer.json file.
---@param projectCommand string either "-project 'path/to/project.xcodeproj'" or "-workspace 'path/to/workspace.xcworkspace'"
---@param scheme string
---@return number # job id
function M.run_config(projectCommand, scheme)
  return vim.fn.jobstart("xcode-build-server config " .. projectCommand .. " -scheme '" .. scheme .. "'", {
    on_exit = function()
      require("xcodebuild.integrations.lsp").restart_sourcekit_lsp()
    end,
  })
end

return M
