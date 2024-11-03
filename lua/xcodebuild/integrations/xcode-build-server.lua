---@mod xcodebuild.integrations.xcode-build-server xcode-build-server Integration
---@brief [[
---This module is responsible for the integration with xcode-build-server.
---
---See: https://github.com/SolaWing/xcode-build-server
---
---@brief ]]

local config = require("xcodebuild.core.config").options.integrations.xcode_build_server
local util = require("xcodebuild.util")

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
---@param projectFile string
---@param scheme string
---@return number # job id
function M.run_config(projectFile, scheme)
  local command = {
    "xcode-build-server",
    "config",
    util.has_suffix(projectFile, "xcodeproj") and "-project" or "-workspace",
    projectFile,
    "-scheme",
    scheme,
  }

  return vim.fn.jobstart(command, {
    on_exit = function()
      require("xcodebuild.integrations.lsp").restart_sourcekit_lsp()
    end,
  })
end

return M
