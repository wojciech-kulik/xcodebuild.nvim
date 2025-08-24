---@mod xcodebuild.ui.pickers Pickers
---@tag xcodebuild.pickers
---@brief [[
---This module is responsible for showing pickers.
---
---Device picker shortcuts:
---<C-r> - Refresh the picker results
---<M-y> - Move the selected item up
---<M-e> - Move the selected item down
---<M-d> - Remove the selected item
---<M-a> - Add a new device
---
---@brief ]]

---@class PickerOptions
---@field on_refresh function|nil # function to call when refresh mapping is triggered
---@field modifiable boolean|nil # allow modifying the results (moving, deleting, adding)
---@field auto_select boolean|nil # if one result, select it automatically
---@field close_on_select boolean|nil # close the picker after selection
---@field device_select_callback function|nil # callback used when selecting a device in non-add mode

local util = require("xcodebuild.util")
local notifications = require("xcodebuild.broadcasting.notifications")
local events = require("xcodebuild.broadcasting.events")
local xcode = require("xcodebuild.core.xcode")
local config = require("xcodebuild.core.config").options
local projectConfig = require("xcodebuild.project.config")
local snapshots = require("xcodebuild.tests.snapshots")
local deviceProxy = require("xcodebuild.platform.device_proxy")

local M = {}

---@class PickerIntegration
local integration = nil
local currentJobId = nil

---Sorts paths by length and then by name.
---@param paths string[]
local function sort_paths(paths)
  table.sort(paths, function(a, b)
    if #a < #b then
      return true
    elseif #a == #b then
      return a:lower() < b:lower()
    else
      return false
    end
  end)
end

---Prepares the picker titles and values for paths from the command output.
---@param command string|string[]
---@return string[], string[]
local function get_picker_titles_values(command)
  local pickerTitles = {}
  local pickerValues = {}
  local paths = util.shell(command)
  sort_paths(paths)

  for _, path in ipairs(paths) do
    if util.trim(path) ~= "" then
      local trimmedPath = path:gsub("/+$", "")
      table.insert(pickerValues, trimmedPath)

      local escapedCwd = vim.fn.getcwd():gsub("(%W)", "%%%1")
      local relativePath = path:gsub(escapedCwd, ""):gsub("^/+", ""):gsub("/+$", "")
      table.insert(pickerTitles, relativePath)
    end
  end

  return pickerTitles, pickerValues
end

---Updates the results of the picker and stops the animation.
---@param results any[]
---@param force boolean|nil
local function update_results(results, force)
  if currentJobId == nil and not force then
    return
  end

  integration.stop_progress()
  integration.update_results(results)
end

---Closes the active picker.
function M.close()
  integration.close()
end

---Shows a picker.
---@param title string
---@param items any[]
---@param callback fun(result: {index: number, value: any}, index: number)|nil
---@param opts PickerOptions|nil
function M.show(title, items, callback, opts)
  if currentJobId then
    vim.fn.jobstop(currentJobId)
    currentJobId = nil
  end

  integration.show(title, items, opts, callback)
end

---Shows a multiselect picker.
---@param title string
---@param items any[]
---@param callback fun(result: any[])|nil
---@param opts PickerOptions|nil
function M.show_multiselect(title, items, callback, opts)
  if currentJobId then
    vim.fn.jobstop(currentJobId)
    currentJobId = nil
  end

  integration.show_multiselect(title, items, opts, callback)
end

---Shows a picker with the available `xcodeproj` files
---if this is not already set in the project settings.
---If the `xcworkspace` is set and there is the corresponding
---`xcodeproj` file with the same name, it will be selected automatically.
---If the project is configured for Swift Package, it returns `nil`.
---@param callback fun(xcodeproj: string|nil)|nil
---@param opts PickerOptions|nil
function M.select_xcodeproj_if_needed(callback, opts)
  if projectConfig.settings.swiftPackage then
    util.call(callback)
    return
  end

  if projectConfig.settings.xcodeproj then
    util.call(callback, projectConfig.settings.xcodeproj)
    return
  end

  local projectFile = projectConfig.settings.projectFile or ""
  local xcodeproj = string.gsub(projectFile, ".xcworkspace", ".xcodeproj")

  if util.file_exists(xcodeproj) then
    projectConfig.settings.xcodeproj = xcodeproj
    projectConfig.save_settings()
    util.call(callback, xcodeproj)
  else
    M.select_xcodeproj(callback, opts)
  end
end

---Shows a picker with `xcodeproj` files
---@param callback fun(xcodeproj: string)|nil
---@param opts PickerOptions|nil
function M.select_xcodeproj(callback, opts)
  local maxdepth = config.commands.project_search_max_depth
  -- stylua: ignore
  local cmd = {
    "find",
    vim.fn.getcwd(),
    "-type", "d",
    "-path", "*/.*", "-prune",
    "-o",
    "-maxdepth", tostring(maxdepth),
    "-iname", "*.xcodeproj",
    "-print",
  }

  if util.is_fd_installed() then
    -- stylua: ignore
    cmd = {
      "fd",
      "-I",
      ".*\\.xcodeproj$",
      vim.fn.getcwd(),
      "--max-depth", tostring(maxdepth),
      "--type", "d",
    }
  end

  local pickerTitles, pickerValues = get_picker_titles_values(cmd)

  M.show("Select Project", pickerTitles, function(_, index)
    local selectedFile = pickerValues[index]

    projectConfig.settings.xcodeproj = selectedFile
    projectConfig.save_settings()
    util.call(callback, selectedFile)
  end, opts)
end

---Shows a picker with `xcworkspace`, `xcodeproj`, and `Package.swift` files.
---@param callback fun(projectFile: string)|nil
---@param opts PickerOptions|nil
function M.select_project(callback, opts)
  local maxdepth = config.commands.project_search_max_depth
  -- stylua: ignore
  local cmd = {
    "find",
    vim.fn.getcwd(),
    "-type", "d",
    "(", "-path", "*/.*", "-o", "-path", "*xcodeproj/project.xcworkspace", ")",
    "-prune",
    "-o",
    "(", "-iname", "*.xcodeproj", "-o", "-iname", "*.xcworkspace", "-o", "-iname", "package.swift", ")",
    "-maxdepth", tostring(maxdepth),
    "-print"
  }

  if util.is_fd_installed() then
    -- stylua: ignore
    cmd = {
      "fd",
      "-I",
      "(.*\\.xcodeproj$|.*\\.xcworkspace$|^Package\\.swift$)",
      vim.fn.getcwd(),
      "--max-depth", tostring(maxdepth),
      "-E", "**/*xcodeproj/project.xcworkspace/"
    }
  end

  local pickerTitles, pickerValues = get_picker_titles_values(cmd)

  M.show("Select Main Project File", pickerTitles, function(_, index)
    local projectFile = pickerValues[index]
    local isSPM = util.has_suffix(projectFile, ".swift")

    projectConfig.settings.workingDirectory = vim.fs.dirname(projectFile)

    if isSPM then
      projectConfig.settings.swiftPackage = projectFile
      projectConfig.settings.xcodeproj = nil
      projectConfig.settings.projectFile = nil
    else
      local isXcodeproj = util.has_suffix(projectFile, "xcodeproj")

      projectConfig.settings.swiftPackage = nil
      projectConfig.settings.xcodeproj = isXcodeproj and projectFile or nil
      projectConfig.settings.projectFile = projectFile
    end

    local xcodeBuildServer = require("xcodebuild.integrations.xcode-build-server")
    xcodeBuildServer.clear_cached_schemes()

    projectConfig.save_settings()
    xcodeBuildServer.run_config_if_enabled()
    util.call(callback, projectFile)
  end, opts)
end

---Shows a picker with the available schemes.
---@param callback fun(scheme: string)|nil
---@param opts PickerOptions|nil
function M.select_scheme(callback, opts)
  local xcodeproj = projectConfig.settings.xcodeproj
  local workingDirectory = projectConfig.settings.workingDirectory
  if not xcodeproj and not workingDirectory then
    notifications.send_error("Project file not set")
    return
  end

  opts = opts or {}

  local xcodeBuildServer = require("xcodebuild.integrations.xcode-build-server")

  local function selectScheme(scheme)
    projectConfig.settings.scheme = scheme
    projectConfig.save_settings()
    xcodeBuildServer.run_config_if_enabled(scheme)

    vim.defer_fn(function()
      util.call(callback, scheme)
    end, 100)
  end

  integration.start_progress()
  M.show("Select Scheme", {}, function(entry, _)
    if entry.value == "[Reload Schemes]" then
      update_results({}, true)
      integration.stop_progress()
      currentJobId = xcode.get_project_information(
        projectConfig.settings.projectFile,
        workingDirectory,
        function(settings)
          update_results(settings.schemes, true)
        end
      )
    else
      selectScheme(entry.value)
    end
  end, opts)

  currentJobId = xcode.find_schemes(xcodeproj, workingDirectory, function(schemes)
    local names = util.select(schemes, function(scheme)
      return scheme.name
    end)

    xcodeBuildServer.update_cached_schemes(names)

    table.insert(names, "[Reload Schemes]")
    update_results(names, true)

    if #names == 1 then
      notifications.send_error("No schemes found")
    elseif #names == 2 and opts.auto_select then
      selectScheme(names[1])
    end
  end)
end

---Shows a picker with the available test plans.
---@param callback fun(testPlan: string|nil)|nil
---@param opts PickerOptions|nil
---@return number|nil job id
function M.select_testplan(callback, opts)
  if projectConfig.settings.swiftPackage then
    projectConfig.settings.testPlan = nil
    projectConfig.save_settings()
    events.project_settings_updated(projectConfig.settings)
    integration.close()
    util.call(callback)
    return nil
  end

  local projectFile = projectConfig.settings.projectFile
  local scheme = projectConfig.settings.scheme

  if not projectFile or not scheme then
    notifications.send_error("Project file and/or scheme not set")
    return nil
  end

  opts = opts or {}

  local function selectTestPlan(testPlan)
    projectConfig.settings.testPlan = testPlan
    projectConfig.save_settings()
    events.project_settings_updated(projectConfig.settings)
    util.call(callback, testPlan)
  end

  integration.start_progress()
  M.show("Select Test Plan", {}, function(entry, _)
    selectTestPlan(entry.value)
  end, opts)

  currentJobId = xcode.get_testplans(projectFile, scheme, function(testPlans)
    if currentJobId and util.is_empty(testPlans) then
      vim.defer_fn(function()
        notifications.send_warning("Could not detect test plans")
      end, 100)

      projectConfig.settings.testPlan = nil
      projectConfig.save_settings()
      events.project_settings_updated(projectConfig.settings)
      integration.close()
      util.call(callback)
    else
      update_results(testPlans)

      if opts.auto_select and testPlans and #testPlans == 1 then
        selectTestPlan(testPlans[1])
        integration.close()
      end
    end
  end)

  return currentJobId
end

---Shows a picker with the available devices.
---It returns devices from cache if available.
---@param callback fun(destination: Device[])|nil
---@param addMode boolean|nil if true, it will add the selected device to the cache
---@param opts PickerOptions|nil
---@return number|nil job id if launched
---@see xcodebuild.config
function M.select_destination(callback, addMode, opts)
  opts = opts or {}

  local projectFile = projectConfig.settings.projectFile
  local swiftPackage = projectConfig.settings.swiftPackage
  local scheme = projectConfig.settings.scheme
  local workingDirectory = projectConfig.settings.workingDirectory
  local results = {}

  if not addMode and projectConfig.is_device_cache_valid() then
    results = projectConfig.device_cache.devices or {}
    projectConfig.update_device_cache(results)
  end

  local hasCachedDevices = util.is_not_empty(results)

  if not (projectFile or swiftPackage) or not scheme then
    notifications.send_error("Project file and/or scheme not set")
    return nil
  end

  local refreshDevices = function(connectedDevices)
    currentJobId = xcode.get_destinations(projectFile, scheme, workingDirectory, function(destinations)
      local availablePlatforms = {}
      for _, destination in ipairs(destinations) do
        availablePlatforms[destination.platform] = true
      end

      for _, device in ipairs(connectedDevices) do
        if availablePlatforms[device.platform] then
          table.insert(destinations, 1, device)
        end
      end

      local alreadyAdded = {}

      if addMode then
        local cache = projectConfig.device_cache and projectConfig.device_cache.devices or {}
        for _, destination in ipairs(cache) do
          alreadyAdded[destination.id] = true
        end
      end

      local filtered = util.filter(destinations, function(table)
        if table.id and not alreadyAdded[table.id] then
          alreadyAdded[table.id] = true

          return (not table.name or not string.find(table.name, "^Any")) and not table.error
        end

        return false
      end)

      if not addMode then
        projectConfig.update_device_cache(filtered)
      end
      results = filtered
      update_results(results)
    end)

    return currentJobId
  end

  local function getConnectedDevices()
    if not deviceProxy.is_enabled() then
      return refreshDevices({})
    end

    return deviceProxy.get_connected_devices(refreshDevices)
  end

  if not hasCachedDevices then
    require("xcodebuild.helpers").defer_send("Loading devices...")
    integration.start_progress()
  end

  opts.on_refresh = getConnectedDevices
  opts.modifiable = not addMode
  opts.device_select_callback = not addMode and callback or nil

  if addMode then
    M.show_multiselect("Add Device(s)", results, function(entry)
      local cache = projectConfig.device_cache.devices or {}
      for _, device in ipairs(entry) do
        table.insert(cache, device)
      end
      projectConfig.update_device_cache(cache)
      util.call(callback, entry)
    end, opts)
  else
    M.show("Select Device", results, function(entry, _)
      projectConfig.set_destination(entry.value)
      util.call(callback, entry.value)
    end, opts)
  end

  if not hasCachedDevices then
    return getConnectedDevices()
  end
end

---Shows a picker with the available failing snapshots.
function M.select_failing_snapshot_test()
  local failingSnapshots = snapshots.get_failing_snapshots()
  local filenames = util.select(failingSnapshots, function(item)
    return util.get_filename(item)
  end)

  M.show("Failing Snapshot Tests", filenames, function(_, index)
    local selectedFile = failingSnapshots[index]
    vim.fn.jobstart({ "qlmanage", "-p", selectedFile }, {
      detach = true,
      on_exit = function() end,
    })

    -- HACK: the preview stays behind the terminal window
    -- when Neovim is running in tmux or zellij.
    if vim.env.TERM_PROGRAM == "tmux" or vim.env.ZELLIJ_PANE_ID then
      vim.defer_fn(function()
        util.shell("open -a qlmanage")
      end, 100)
    end
  end)
end

---Shows a picker with the available actions.
---If the project is not configured, it will show the configuration wizard.
function M.show_all_actions()
  local pickerActions = require("xcodebuild.ui.picker_actions")

  if not projectConfig.is_configured() then
    local actions = require("xcodebuild.actions")
    local actionsNames = { "Show Configuration Wizard" }
    local actionsPointers = { actions.configure_project }

    M.show("Xcodebuild Actions", actionsNames, function(_, index)
      local selectSchemeIndex = util.indexOf(actionsNames, "Select Scheme")

      if #actionsNames == 1 or index >= selectSchemeIndex then
        actionsPointers[index]()
      else
        vim.defer_fn(actionsPointers[index], 100)
      end
    end, { close_on_select = true })
  elseif projectConfig.is_app_configured() then
    pickerActions.show_xcode_project_actions()
  elseif projectConfig.is_library_configured() then
    pickerActions.show_library_project_actions()
  elseif projectConfig.is_spm_configured() then
    pickerActions.show_spm_actions()
  end
end

function M.setup()
  integration = require("xcodebuild.integrations.telescope")
end

return M
