---@mod xcodebuild.integrations.xcode_build_server xcode-build-server Integration
---@brief [[
---This module is responsible for the integration with xcode-build-server.
---It provides a function to update buildServer.json file with the current scheme.
---@brief ]]

local M = {}

---Calls "config" command of xcode-build-server in order to update buildServer.json file.
---@param scheme string
function M.run_config(projectCommand, scheme)
  vim.fn.jobstart("xcode-build-server config " .. projectCommand .. " -scheme '" .. scheme .. "'")
end

return M
