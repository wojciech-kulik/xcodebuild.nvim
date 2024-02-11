local M = {}

function M.setup()
  local config = require("xcodebuild.config").options.integrations.nvim_tree
  if not config.enabled then
    return
  end

  local success, api = pcall(require, "nvim-tree.api")
  if not success then
    return
  end

  local projectManager = require("xcodebuild.project_manager")
  local projectConfig = require("xcodebuild.project_config")
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
