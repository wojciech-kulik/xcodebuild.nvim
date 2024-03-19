---@mod xcodebuild.integrations.oil-nvim oil.nvim Integration
---@brief [[
---This module is responsible for the integration with `oil.nvim`.
---It listens to `oil.nvim` events and updates the project file accordingly.
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
---  https://github.com/stevearc/oil.nvim
---
---@brief ]]

local M = {}

---Sets up the integration with `oil.nvim`.
---It subscribes to `oil.nvim` events.
---@see xcodebuild.project-manager
function M.setup()
  local config = require("xcodebuild.core.config").options.integrations.oil_nvim
  if not config.enabled then
    return
  end

  local success, _ = pcall(require, "oil")
  if not success then
    return
  end

  local projectManager = require("xcodebuild.project.manager")
  local projectConfig = require("xcodebuild.project.config")
  local cwd = vim.fn.getcwd()

  local function isProjectFile(path)
    return projectConfig.is_project_configured() and vim.startswith(path, cwd)
  end

  local function shouldUpdateProject(path)
    return isProjectFile(path) and config.should_update_project(path)
  end

  ---@param url string
  ---@return string|nil
  local function parseUrl(url)
    if not url then
      return nil
    end

    return url:match("^.*://(.*)$")
  end

  vim.api.nvim_create_autocmd("User", {
    group = vim.api.nvim_create_augroup("xcodebuild-integrations-oil", { clear = true }),
    pattern = "OilActionsPost",
    callback = function(args)
      if args.data.err then
        return
      end

      local co = coroutine.create(function(co)
        for _, action in ipairs(args.data.actions) do
          local path = parseUrl(action.url) or parseUrl(action.src_url)

          if not path or not shouldUpdateProject(path) then
            return
          end

          local function addFileAndWaitForTargetSelection(atPath)
            projectManager.add_file(atPath, function()
              coroutine.resume(co, co)
            end)
            coroutine.yield()
          end

          if action.type == "create" then
            if action.entry_type == "directory" then
              projectManager.add_group(path)
            elseif action.entry_type == "file" then
              addFileAndWaitForTargetSelection(path)
            end
          elseif action.type == "copy" then
            local destPath = parseUrl(action.dest_url)
            if destPath then
              if action.entry_type == "directory" then
                vim.notify('xcodebuild.nvim: action "copy directory" is not supported', vim.log.levels.WARN)
              elseif action.entry_type == "file" then
                addFileAndWaitForTargetSelection(destPath)
              end
            end
          elseif action.type == "delete" then
            if action.entry_type == "directory" then
              projectManager.delete_group(path)
            elseif action.entry_type == "file" then
              projectManager.delete_file(path)
            end
          elseif action.type == "move" then
            if action.entry_type == "directory" then
              local destPath = parseUrl(action.dest_url)
              if destPath then
                projectManager.move_or_rename_group(path, destPath)
              end
            elseif action.entry_type == "file" then
              local destPath = parseUrl(action.dest_url)
              if destPath then
                projectManager.move_file(path, destPath)
              end
            end
          end
        end
      end)

      coroutine.resume(co, co)
    end,
  })
end

return M
