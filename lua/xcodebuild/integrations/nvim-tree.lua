---@mod xcodebuild.integrations.nvim_tree nvim-tree Integration
---@brief [[
---This module is responsible for the integration with `nvim-tree`.
---It listens to `nvim-tree` events and updates the project file accordingly.
---
---The integrations is enabled only if the current working directory
---contains the project configuration (|xcodebuild.project.config|).
---
---You can always disable the integration in the |xcodebuild.config|.
---
---This feature requires `Xcodeproj` to be installed (|xcodebuild.requirements|).
---
---See:
---  |xcodebuild.project-manager|
---  https://github.com/nvim-tree/nvim-tree.lua
---  https://github.com/wojciech-kulik/xcodebuild.nvim#-nvim-tree-integration
---
---@brief ]]

local M = {}

---Sets up the integration with `nvim-tree`.
---It subscribes to `nvim-tree` events.
---@see xcodebuild.project-manager
function M.setup()
  local config = require("xcodebuild.core.config").options.integrations.nvim_tree
  if not config.enabled then
    return
  end

  local success, api = pcall(require, "nvim-tree.api")
  if not success then
    return
  end

  local projectManager = require("xcodebuild.project.manager")
  local projectConfig = require("xcodebuild.project.config")
  local Event = api.events.Event
  local cwd = vim.fn.getcwd()

  local function isProjectFile(path)
    return projectConfig.is_project_configured() and vim.startswith(path, cwd)
  end

  local function shouldUpdateProject(path)
    return isProjectFile(path) and config.should_update_project(path)
  end

  api.events.subscribe(Event.NodeRenamed, function(data)
    if shouldUpdateProject(data.old_name) then
      local isDir = vim.fn.isdirectory(data.new_name) == 1
      if isDir then
        projectManager.move_or_rename_group(data.old_name, data.new_name)
      else
        projectManager.move_file(data.old_name, data.new_name)
      end
    end
  end)

  api.events.subscribe(Event.FileRemoved, function(data)
    if shouldUpdateProject(data.fname) then
      projectManager.delete_file(data.fname)
    end
  end)

  api.events.subscribe(Event.FileCreated, function(data)
    if shouldUpdateProject(data.fname) then
      projectManager.add_file(data.fname)
    end
  end)

  api.events.subscribe(Event.FolderCreated, function(data)
    local isDir = vim.fn.isdirectory(data.folder_name) == 1

    if shouldUpdateProject(data.folder_name) and isDir then
      projectManager.add_group(data.folder_name)
    end
  end)

  api.events.subscribe(Event.FolderRemoved, function(data)
    if shouldUpdateProject(data.folder_name) then
      projectManager.delete_group(data.folder_name)
    end
  end)
end

return M
