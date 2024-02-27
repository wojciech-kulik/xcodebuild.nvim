---@mod xcodebuild.integrations.xcode_build_server xcode-build-server Integration
---@brief [[
---This module is responsible for the integration with xcode-build-server.
---It provides a function to update buildServer.json file with the current scheme.
---@brief ]]

local M = {}

---Calls "config" command of xcode-build-server in order to update buildServer.json file.
---@param projectCommand string either "-project 'path/to/project.xcodeproj'" or "-workspace 'path/to/workspace.xcworkspace'"
---@param scheme string
---@return number # job id
function M.run_config(projectCommand, scheme)
  return vim.fn.jobstart("xcode-build-server config " .. projectCommand .. " -scheme '" .. scheme .. "'")
end

return M
