---@mod xcodebuild.ui.pickers Pickers
---@tag xcodebuild.pickers
---@brief [[
---This module is responsible for showing pickers using Telescope.nvim.
---
---Device picker shortcuts:
---<C-r> - Refresh the picker results
---<M-y> - Move the selected item up
---<M-e> - Move the selected item down
---<M-x> - Remove the selected item
---<M-a> - Add a new device
---
---@brief ]]

---@class PickerOptions
---@field on_refresh function|nil
---@field multiselect boolean|nil
---@field modifiable boolean|nil
---@field auto_select boolean|nil
---@field close_on_select boolean|nil
---@field device_select_callback function|nil

local helpers = require("xcodebuild.helpers")
local util = require("xcodebuild.util")
local notifications = require("xcodebuild.broadcasting.notifications")
local constants = require("xcodebuild.core.constants")
local events = require("xcodebuild.broadcasting.events")
local xcode = require("xcodebuild.core.xcode")
local config = require("xcodebuild.core.config").options
local projectConfig = require("xcodebuild.project.config")
local snapshots = require("xcodebuild.tests.snapshots")
local deviceProxy = require("xcodebuild.platform.device_proxy")

local telescopePickers = require("telescope.pickers")
local telescopeFinders = require("telescope.finders")
local telescopeConfig = require("telescope.config").values
local telescopeActions = require("telescope.actions")
local telescopeState = require("telescope.actions.state")
local telescopeActionsUtils = require("telescope.actions.utils")

local M = {}

local currentJobId = nil
local activePicker = nil
local progressTimer = nil
local currentProgressFrame = 1
local progressFrames = {
  "[      ]",
  "[ .    ]",
  "[ ..   ]",
  "[ ...  ]",
  "[  ... ]",
  "[   .. ]",
  "[    . ]",
}

---Gets user-friendly device name
---@param destination XcodeDevice
---@return string
local function get_destination_name(destination)
  local name = destination.name or ""
  local isDevice = constants.is_device(destination.platform)
  local isSimulator = constants.is_simulator(destination.platform)

  if destination.platform and isDevice then
    return util.trim(name) .. (destination.os and " (" .. destination.os .. ")" or "")
  end

  if destination.platform and not isSimulator then
    name = util.trim(name .. " " .. destination.platform)
  end
  if destination.platform == constants.Platform.MACOS and destination.arch then
    name = name .. " (" .. destination.arch .. ")"
  end
  if destination.os then
    name = name .. " (" .. destination.os .. ")"
  end
  if destination.variant then
    name = name .. " (" .. destination.variant .. ")"
  end
  if destination.error then
    name = name .. " [error]"
  end

  return name
end

---Creates a picker entry.
---@param entry string|XcodeDevice
---@return table
local function entry_maker(entry)
  if type(entry) == "table" and entry.id then
    local name = get_destination_name(entry)
    return {
      value = entry,
      display = name,
      ordinal = name,
    }
  end

  return {
    value = entry,
    display = entry,
    ordinal = entry,
  }
end

---Stops the spinner animation.
local function stop_telescope_spinner()
  if progressTimer then
    vim.fn.timer_stop(progressTimer)
    progressTimer = nil
  end
end

---Updates the spinner animation.
local function update_telescope_spinner()
  if activePicker and vim.api.nvim_win_is_valid(activePicker.results_win) then
    currentProgressFrame = currentProgressFrame >= #progressFrames and 1 or currentProgressFrame + 1
    activePicker:change_prompt_prefix(progressFrames[currentProgressFrame] .. " ", "TelescopePromptPrefix")
  else
    stop_telescope_spinner()
  end
end

---Starts the spinner animation.
local function start_telescope_spinner()
  if not progressTimer then
    progressTimer = vim.fn.timer_start(80, update_telescope_spinner, { ["repeat"] = -1 })
  end
end

---Updates the results of the picker and stops the animation.
---@param results string[]|XcodeDevice[]
---@param force boolean|nil
local function update_results(results, force)
  if currentJobId == nil and not force then
    return
  end

  stop_telescope_spinner()

  if activePicker then
    activePicker:refresh(
      telescopeFinders.new_table({
        results = results,
        entry_maker = entry_maker,
      }),
      {
        new_prefix = telescopeConfig.prompt_prefix,
      }
    )
  end
end

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

local function swap_entries(entries, index1, index2)
  local tmp = entries[index1]
  entries[index1] = entries[index2]
  entries[index2] = tmp
end

---Sets the picker actions for moving and deleting items.
---@param bufnr number
---@param opts PickerOptions|nil
local function set_picker_actions(bufnr, opts)
  local mappings = require("xcodebuild.core.config").options.device_picker.mappings
  local actionState = require("telescope.actions.state")
  local get_entries = function()
    if not activePicker then
      return {}
    end

    local entries = {}
    for entry in activePicker.manager:iter() do
      table.insert(entries, entry.value)
    end

    return entries
  end

  vim.keymap.set({ "n", "i" }, mappings.move_up_device, function()
    if actionState.get_current_line() ~= "" then
      return
    end

    local entries = get_entries()
    local currentEntry = actionState.get_selected_entry()
    if currentEntry then
      local index = currentEntry.index
      if index == 1 then
        return
      end

      swap_entries(entries, index, index - 1)
      swap_entries(projectConfig.device_cache.devices, index, index - 1)
      projectConfig.save_device_cache()
      update_results(entries, true)

      vim.defer_fn(function()
        if activePicker then
          activePicker:set_selection(index - 2)
        end
      end, 50)
    end
  end, { buffer = bufnr })

  vim.keymap.set({ "n", "i" }, mappings.move_down_device, function()
    if actionState.get_current_line() ~= "" then
      return
    end

    local entries = get_entries()
    local currentEntry = actionState.get_selected_entry()

    if currentEntry then
      local index = currentEntry.index
      if index == #entries then
        return
      end

      swap_entries(entries, index, index + 1)
      swap_entries(projectConfig.device_cache.devices, index, index + 1)
      projectConfig.save_device_cache()
      update_results(entries, true)

      vim.defer_fn(function()
        if activePicker then
          activePicker:set_selection(index)
        end
      end, 50)
    end
  end, { buffer = bufnr })

  vim.keymap.set({ "n", "i" }, mappings.delete_device, function()
    if activePicker and actionState.get_selected_entry() then
      activePicker:delete_selection(function(selection)
        local index = util.indexOfPredicate(projectConfig.device_cache.devices, function(device)
          return device.id == selection.value.id
        end)

        table.remove(projectConfig.device_cache.devices, index)
        projectConfig.save_device_cache()
      end)
    end
  end, { buffer = bufnr })

  vim.keymap.set({ "n", "i" }, mappings.add_device, function()
    M.select_destination(function()
      M.select_destination((opts or {}).device_select_callback, false, opts)
    end, true, { close_on_select = false, multiselect = true })
  end, { buffer = bufnr })
end

---Closes the active picker.
function M.close()
  if activePicker then
    telescopeActions.close(activePicker.prompt_bufnr)
  end
end

---Shows a picker using Telescope.nvim.
---@param title string
---@param items string[]|XcodeDevice[]
---@param callback function|nil
---@param opts PickerOptions|nil
function M.show(title, items, callback, opts)
  local mappings = require("xcodebuild.core.config").options.device_picker.mappings

  if currentJobId then
    vim.fn.jobstop(currentJobId)
    currentJobId = nil
  end

  opts = opts or {}

  activePicker = telescopePickers.new(require("telescope.themes").get_dropdown({}), {
    prompt_title = title,
    finder = telescopeFinders.new_table({
      results = items,
      entry_maker = entry_maker,
    }),
    sorter = telescopeConfig.generic_sorter(),
    file_ignore_patterns = {},
    attach_mappings = function(prompt_bufnr, _)
      if opts.on_refresh ~= nil then
        vim.keymap.set({ "n", "i" }, mappings.refresh_devices, function()
          start_telescope_spinner()
          opts.on_refresh()
        end, { silent = true, buffer = prompt_bufnr })
      end

      if opts.modifiable then
        set_picker_actions(prompt_bufnr, opts)
      end

      telescopeActions.select_default:replace(function()
        local selection = telescopeState.get_selected_entry()

        local results = {}
        if opts.multiselect then
          telescopeActionsUtils.map_selections(prompt_bufnr, function(entry)
            table.insert(results, entry.value)
          end)

          if util.is_empty(results) and selection then
            table.insert(results, selection.value)
          end
        end

        if opts.close_on_select and selection then
          telescopeActions.close(prompt_bufnr)
        end

        if callback and selection then
          if opts.multiselect then
            callback(results)
          else
            callback(selection, selection.index)
          end
        end
      end)
      return true
    end,
  })

  activePicker:find()
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

    require("xcodebuild.project.manager").clear_cached_schemes()

    projectConfig.save_settings()
    helpers.update_xcode_build_server_config()
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

  local function selectScheme(scheme)
    projectConfig.settings.scheme = scheme
    projectConfig.save_settings()
    helpers.update_xcode_build_server_config()

    vim.defer_fn(function()
      util.call(callback, scheme)
    end, 100)
  end

  start_telescope_spinner()
  M.show("Select Scheme", {}, function(entry, _)
    selectScheme(entry.value)
  end, opts)

  currentJobId = xcode.find_schemes(xcodeproj, workingDirectory, function(schemes)
    local names = util.select(schemes, function(scheme)
      return scheme.name
    end)

    update_results(names, true)

    if util.is_empty(names) then
      notifications.send_error("No schemes found")
    elseif #names == 1 and opts.auto_select then
      selectScheme(names[1])
    end
  end)
end

---Shows a picker with the available test plans.
---@param callback fun(testPlan: string|nil)|nil
---@param opts PickerOptions|nil
---@return number|nil job id
function M.select_testplan(callback, opts)
  local function closePicker()
    if activePicker and util.is_not_empty(vim.fn.win_findbuf(activePicker.prompt_bufnr)) then
      telescopeActions.close(activePicker.prompt_bufnr)
    end
  end

  if projectConfig.settings.swiftPackage then
    projectConfig.settings.testPlan = nil
    projectConfig.save_settings()
    events.project_settings_updated(projectConfig.settings)
    closePicker()
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

  start_telescope_spinner()
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
      closePicker()
      util.call(callback)
    else
      update_results(testPlans)

      if opts.auto_select and testPlans and #testPlans == 1 then
        selectTestPlan(testPlans[1])
        closePicker()
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
    start_telescope_spinner()
  end

  opts.on_refresh = getConnectedDevices
  opts.modifiable = not addMode
  opts.device_select_callback = not addMode and callback or nil

  M.show(addMode and "Add Device(s)" or "Select Device", results, function(entry, _)
    if addMode then
      local cache = projectConfig.device_cache.devices or {}
      for _, device in ipairs(entry) do
        table.insert(cache, device)
      end
      projectConfig.update_device_cache(cache)
      util.call(callback, entry)
    else
      projectConfig.set_destination(entry.value)
      util.call(callback, entry.value)
    end
  end, opts)

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

  require("xcodebuild.ui.pickers").show("Failing Snapshot Tests", filenames, function(_, index)
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

return M
