---@mod xcodebuild.integrations.xcode-build-server xcode-build-server Integration
---@brief [[
---This module is responsible for the integration with xcode-build-server.
---
---See: https://github.com/SolaWing/xcode-build-server
---
---@brief ]]

local config = require("xcodebuild.core.config").options.integrations.xcode_build_server
local util = require("xcodebuild.util")
local xcode = require("xcodebuild.core.xcode")
local projectConfig = require("xcodebuild.project.config")
local projectManager = require("xcodebuild.project.manager")
local notifications = require("xcodebuild.broadcasting.notifications")

local M = {}

---Current xcode-build-server job id
---@type number|nil
local configJobId

---Current find schemes job id
---@type number|nil
local findSchemesJobId

---Cached schemes
---@type string[]
local cachedSchemes = {}

---Last selected scheme
---@type string|nil
local lastSelectedScheme

---Finds the first scheme in the project whose name matches one of the provided target names.
---@param targets string[]
---@param schemes string[]
local function select_matching_scheme(targets, schemes)
  for _, target in ipairs(targets) do
    for _, scheme in ipairs(schemes) do
      if target == scheme then
        if lastSelectedScheme ~= scheme then
          notifications.send("Scheme changed to: " .. scheme)
          M.run_config_if_enabled(scheme)
        end

        return
      end
    end
  end
end

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
  lastSelectedScheme = scheme

  local command = {
    "xcode-build-server",
    "config",
    util.has_suffix(projectFile, "xcodeproj") and "-project" or "-workspace",
    projectFile,
    "-scheme",
    scheme,
  }

  if configJobId then
    vim.fn.jobstop(configJobId)
  end

  configJobId = vim.fn.jobstart(command, {
    on_exit = function()
      require("xcodebuild.integrations.lsp").restart_sourcekit_lsp()
    end,
  })

  return configJobId
end

---Calls "config" command of xcode-build-server in order to update buildServer.json file.
---This function is called only if the integration is enabled and the
---xcode-build-server is installed.
---@param scheme string|nil
function M.run_config_if_enabled(scheme)
  if not M.is_enabled() or not M.is_installed() then
    return
  end

  local projectFile = projectConfig.settings.projectFile
  local projectScheme = scheme or projectConfig.settings.scheme

  if projectFile and projectScheme then
    M.run_config(projectFile, projectScheme)
  end
end

---Updates cached schemes.
---@param schemes string[]
function M.update_cached_schemes(schemes)
  cachedSchemes = schemes
end

---Clears cached schemes.
function M.clear_cached_schemes()
  cachedSchemes = {}
end

---@tag xcodebuild.guess-scheme
---This function is responsible for running the `xcode-build-server config` command
---with the scheme matching the current file's target. It's not perfect, because
---schemes can have different names than targets, but it might be helpful in some
---cases.
---
---You can enable it by setting `guess_scheme` to `true` in the configuration.
---It will be triggered every time you enter a `Swift` buffer, so the performance
---might be affected.
---
---Schemes are cached to avoid unnecessary calls to `xcodebuild` when switching
---between files. To clear the cache, you can use the `clear_cached_schemes`
---function, restart Neovim, or show schemes picker.
function M.guess_scheme()
  local xcodeproj = projectConfig.settings.xcodeproj
  local workingDirectory = projectConfig.settings.workingDirectory

  if not xcodeproj and not workingDirectory then
    return
  end

  local fileTargets = projectManager.get_current_file_targets()
  if #fileTargets == 0 then
    notifications.send("No targets found for the current file")
    return
  end

  if #cachedSchemes > 0 then
    select_matching_scheme(fileTargets, cachedSchemes)
    return
  end

  if findSchemesJobId then
    vim.fn.jobstop(findSchemesJobId)
  end

  findSchemesJobId = xcode.find_schemes(xcodeproj, workingDirectory, function(schemes)
    cachedSchemes = vim.tbl_map(function(scheme)
      return scheme.name
    end, schemes)

    select_matching_scheme(fileTargets, cachedSchemes)
  end)
end

function M.setup()
  if config.guess_scheme then
    vim.api.nvim_create_autocmd({ "BufEnter" }, {
      group = vim.api.nvim_create_augroup("xcodebuild-integrations-xcode-build-server", { clear = true }),
      pattern = "*.swift",
      callback = M.guess_scheme,
    })
  end
end

return M
