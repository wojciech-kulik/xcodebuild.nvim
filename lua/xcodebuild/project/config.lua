local xcode = require("xcodebuild.core.xcode")

local M = {
  settings = {},
}

local function get_filepath()
  return vim.fn.getcwd() .. "/.nvim/xcodebuild/settings.json"
end

local function update_global_variables()
  vim.g.xcodebuild_device_name = M.settings.deviceName
  vim.g.xcodebuild_os = M.settings.os
  vim.g.xcodebuild_platform = M.settings.platform
  vim.g.xcodebuild_config = M.settings.config
  vim.g.xcodebuild_scheme = M.settings.scheme
  vim.g.xcodebuild_test_plan = M.settings.testPlan
end

function M.load_settings()
  local success, content = pcall(vim.fn.readfile, get_filepath())

  if success then
    M.settings = vim.fn.json_decode(content)
    update_global_variables()
  end
end

function M.save_settings()
  local json = vim.split(vim.fn.json_encode(M.settings), "\n", { plain = true })
  vim.fn.writefile(json, get_filepath())
  update_global_variables()
end

function M.is_project_configured()
  local settings = M.settings
  return settings.platform
    and settings.projectFile
    and settings.projectCommand
    and settings.scheme
    and settings.config
    and settings.destination
    and settings.bundleId
    and settings.appPath
    and settings.productName
end

function M.update_settings(callback)
  xcode.get_build_settings(
    M.settings.platform,
    M.settings.projectCommand,
    M.settings.scheme,
    M.settings.config,
    function(buildSettings)
      M.settings.appPath = buildSettings.appPath
      M.settings.productName = buildSettings.productName
      M.settings.bundleId = buildSettings.bundleId
      M.save_settings()
      if callback then
        callback()
      end
    end
  )
end

function M.configure_project()
  local appdata = require("xcodebuild.project.appdata")
  local notifications = require("xcodebuild.broadcasting.notifications")

  appdata.create_app_dir()

  local pickers = require("xcodebuild.ui.pickers")
  local defer_print = function(text)
    vim.defer_fn(function()
      notifications.send(text)
    end, 100)
  end

  pickers.select_project(function()
    pickers.select_xcodeproj_if_needed(function()
      defer_print("Loading project information...")
      pickers.select_config(function(projectInfo)
        pickers.select_scheme(projectInfo.schemes, function()
          defer_print("Loading devices...")
          pickers.select_destination(function()
            defer_print("Updating settings...")
            M.update_settings(function()
              defer_print("Loading test plans...")
              pickers.select_testplan(function()
                defer_print("Xcodebuild configuration has been saved!")
              end, { close_on_select = true })
            end)
          end)
        end)
      end)
    end)
  end)
end

return M
