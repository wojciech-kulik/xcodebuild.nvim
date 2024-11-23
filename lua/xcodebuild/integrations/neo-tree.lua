---@mod xcodebuild.integrations.neo-tree neo-tree.nvim Integration
---@brief [[
---This module is responsible for the integration with `neo-tree.nvim`.
---It listens to `neo-tree` events and updates the project file accordingly.
---
---The integration is enabled only if the current working directory
---contains the project configuration (|xcodebuild.project.config|).
---
---You can always disable the integration in the |xcodebuild.config|.
---
---This feature requires `Xcodeproj` to be installed (|xcodebuild.requirements|).
---
---See:
---  |xcodebuild.project-manager|
---  https://github.com/nvim-neo-tree/neo-tree.nvim
---  https://github.com/wojciech-kulik/xcodebuild.nvim/wiki/Integrations#-file-tree-integration
---
---@brief ]]

local M = {}

---Sets up the integration with `neo-tree`.
---It subscribes to `neo-tree` events.
---@see xcodebuild.project-manager
function M.setup()
  local isEnabled = require("xcodebuild.core.config").options.integrations.neo_tree.enabled
  if not isEnabled then
    return
  end

  local success, events = pcall(require, "neo-tree.events")
  if not success then
    return
  end

  local projectManagerConfig = require("xcodebuild.core.config").options.project_manager
  local projectManager = require("xcodebuild.project.manager")
  local projectConfig = require("xcodebuild.project.config")
  local cwd = vim.fn.getcwd()

  local function isProjectFile(path)
    return (projectConfig.is_app_configured() or projectConfig.is_library_configured())
      and vim.startswith(path, cwd)
  end

  local function shouldUpdateProject(path)
    return isProjectFile(path) and projectManagerConfig.should_update_project(path)
  end

  local function moveOrRename(data)
    if not shouldUpdateProject(data.source) then
      return
    end

    local isDir = vim.fn.isdirectory(data.destination) == 1
    if isDir then
      projectManager.move_or_rename_group(data.source, data.destination)
    else
      projectManager.move_file(data.source, data.destination)
    end
  end

  events.subscribe({
    event = "file_added",
    handler = function(path)
      if not shouldUpdateProject(path) then
        return
      end

      local isDir = vim.fn.isdirectory(path) == 1
      if isDir then
        projectManager.add_group(path)
      else
        projectManager.add_file(path, nil, { createGroups = true })
      end
    end,
  })

  events.subscribe({
    event = "file_deleted",
    handler = function(path)
      if not shouldUpdateProject(path) then
        return
      end

      local extension = vim.fn.fnamemodify(path, ":e")
      local isDir = extension == ""

      if isDir then
        projectManager.delete_group(path)
      else
        projectManager.delete_file(path)
      end
    end,
  })

  events.subscribe({
    event = "file_moved",
    handler = moveOrRename,
  })

  events.subscribe({
    event = "file_renamed",
    handler = moveOrRename,
  })
end

return M
