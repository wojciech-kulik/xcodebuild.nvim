---@mod xcodebuild.ui.pickers Pickers
---@tag xcodebuild.pickers
---@brief [[
---This module is responsible for showing pickers using Telescope.nvim.
---@brief ]]

---@class PickerOptions
---@field on_refresh function|nil
---@field multiselect boolean|nil
---@field auto_select boolean|nil
---@field close_on_select boolean|nil

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

local cachedDestinations = {}
local cachedDeviceNames = {}
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

---Updates xcode-build-server config if needed.
local function update_xcode_build_server_config()
  local xcodeBuildServer = require("xcodebuild.integrations.xcode-build-server")

  if not xcodeBuildServer.is_enabled() or not xcodeBuildServer.is_installed() then
    return
  end

  local projectCommand = projectConfig.settings.projectCommand
  local scheme = projectConfig.settings.scheme

  if projectCommand and scheme then
    xcodeBuildServer.run_config(projectCommand, scheme)
  end
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
---@param results string[]
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
---@param command string
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

---Shows a picker using Telescope.nvim.
---@param title string
---@param items string[]
---@param callback function|nil
---@param opts PickerOptions|nil
function M.show(title, items, callback, opts)
  if currentJobId then
    vim.fn.jobstop(currentJobId)
    currentJobId = nil
  end

  opts = opts or {}

  activePicker = telescopePickers.new(require("telescope.themes").get_dropdown({}), {
    prompt_title = title,
    finder = telescopeFinders.new_table({
      results = items,
    }),
    sorter = telescopeConfig.generic_sorter(),
    file_ignore_patterns = {},
    attach_mappings = function(prompt_bufnr, _)
      if opts.on_refresh ~= nil then
        vim.keymap.set({ "n", "i" }, "<C-r>", function()
          start_telescope_spinner()
          opts.on_refresh()
        end, { silent = true, buffer = prompt_bufnr })
      end

      telescopeActions.select_default:replace(function()
        local selection = telescopeState.get_selected_entry()

        local results = {}
        if opts.multiselect then
          telescopeActionsUtils.map_selections(prompt_bufnr, function(sel)
            table.insert(results, sel[1])
          end)

          if util.is_empty(results) and selection then
            table.insert(results, selection[1])
          end
        end

        if opts.close_on_select and selection then
          telescopeActions.close(prompt_bufnr)
        end

        if callback and selection then
          if opts.multiselect then
            callback(results)
          else
            callback(selection[1], selection.index)
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
  local cmd = "find '"
    .. vim.fn.getcwd()
    .. "' -type d -path '*/.*' -prune -o -maxdepth "
    .. maxdepth
    .. " -iname '*.xcodeproj' -print"
    .. " 2> /dev/null"

  if util.is_fd_installed() then
    cmd = "fd -I '.*\\.xcodeproj$' '"
      .. vim.fn.getcwd()
      .. "' --max-depth "
      .. maxdepth
      .. " --type d 2> /dev/null"
  end

  local pickerTitles, pickerValues = get_picker_titles_values(cmd)

  M.show("Select Project", pickerTitles, function(_, index)
    local selectedFile = pickerValues[index]

    projectConfig.settings.xcodeproj = selectedFile
    projectConfig.save_settings()
    util.call(callback, selectedFile)
  end, opts)
end

---Shows a picker with `xcworkspace` and `xcodeproj` files.
---@param callback fun(projectFile: string)|nil
---@param opts PickerOptions|nil
function M.select_project(callback, opts)
  local maxdepth = config.commands.project_search_max_depth
  local cmd = "find '"
    .. vim.fn.getcwd()
    .. "' -type d \\( -path '*/.*' -o -path '*xcodeproj/project.xcworkspace' \\) -prune -o"
    .. " \\( -iname '*.xcodeproj' -o -iname '*.xcworkspace' -o -iname 'package.swift' \\)"
    .. " -maxdepth "
    .. maxdepth
    .. " -print 2> /dev/null"

  if util.is_fd_installed() then
    cmd = "fd -I '(.*\\.xcodeproj$|.*\\.xcworkspace$|Package\\.swift$)' '"
      .. vim.fn.getcwd()
      .. "' --max-depth "
      .. maxdepth
      .. " -E '**/*xcodeproj/project.xcworkspace/' 2> /dev/null"
  end

  local pickerTitles, pickerValues = get_picker_titles_values(cmd)

  M.show("Select Main Project File", pickerTitles, function(_, index)
    local projectFile = pickerValues[index]
    local isSPM = util.has_suffix(projectFile, "Package.swift")

    projectConfig.settings.workingDirectory = vim.fs.dirname(projectFile)

    if isSPM then
      projectConfig.settings.swiftPackage = projectFile
      projectConfig.settings.xcodeproj = nil
      projectConfig.settings.projectFile = nil
      projectConfig.settings.projectCommand = nil
    else
      local isWorkspace = util.has_suffix(projectFile, "xcworkspace")
      local isXcodeproj = util.has_suffix(projectFile, "xcodeproj")

      projectConfig.settings.swiftPackage = nil
      projectConfig.settings.xcodeproj = isXcodeproj and projectFile or nil
      projectConfig.settings.projectFile = projectFile
      projectConfig.settings.projectCommand = (isWorkspace and "-workspace '" or "-project '")
        .. projectFile
        .. "'"
    end

    projectConfig.save_settings()
    update_xcode_build_server_config()
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
    update_xcode_build_server_config()

    vim.defer_fn(function()
      util.call(callback, scheme)
    end, 100)
  end

  start_telescope_spinner()
  M.show("Select Scheme", {}, function(value, _)
    selectScheme(value)
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

  local projectCommand = projectConfig.settings.projectCommand
  local scheme = projectConfig.settings.scheme

  if not projectCommand or not scheme then
    notifications.send_error("Project command and/or scheme not set")
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
  M.show("Select Test Plan", {}, function(value, _)
    selectTestPlan(value)
  end, opts)

  currentJobId = xcode.get_testplans(projectCommand, scheme, function(testPlans)
    if currentJobId and util.is_empty(testPlans) then
      vim.defer_fn(function()
        notifications.send_warning("Could not detect test plans")
      end, 100)

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
---It returns devices from cache if available and the `cache_devices`
---option in config is enabled.
---@param callback fun(destination: Device[])|nil
---@param opts PickerOptions|nil
---@return number|nil job id if launched
---@see xcodebuild.config
function M.select_destination(callback, opts)
  opts = opts or {}

  local projectCommand = projectConfig.settings.projectCommand
  local swiftPackage = projectConfig.settings.swiftPackage
  local scheme = projectConfig.settings.scheme
  local workingDirectory = projectConfig.settings.workingDirectory
  local results = cachedDestinations or {}
  local useCache = config.commands.cache_devices
  local hasCachedDevices = useCache and util.is_not_empty(results) and util.is_not_empty(cachedDeviceNames)

  if not (projectCommand or swiftPackage) or not scheme then
    notifications.send_error("Project command and/or scheme not set")
    return nil
  end

  local refreshDevices = function(connectedDevices)
    currentJobId = xcode.get_destinations(projectCommand, scheme, workingDirectory, function(destinations)
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
      local filtered = util.filter(destinations, function(table)
        if table.id and not alreadyAdded[table.id] then
          alreadyAdded[table.id] = true

          return (not table.name or not string.find(table.name, "^Any")) and not table.error
        end

        return false
      end)

      local destinationNames = util.select(filtered, function(table)
        local name = table.name or ""
        local isDevice = constants.is_device(table.platform)
        local isSimulator = constants.is_simulator(table.platform)

        if table.platform and isDevice then
          return util.trim(name) .. (table.os and " (" .. table.os .. ")" or "")
        end

        if table.platform and not isSimulator then
          name = util.trim(name .. " " .. table.platform)
        end
        if table.platform == constants.Platform.MACOS and table.arch then
          name = name .. " (" .. table.arch .. ")"
        end
        if table.os then
          name = name .. " (" .. table.os .. ")"
        end
        if table.variant then
          name = name .. " (" .. table.variant .. ")"
        end
        if table.error then
          name = name .. " [error]"
        end
        return name
      end)

      if useCache then
        cachedDeviceNames = destinationNames
        cachedDestinations = filtered
      end

      results = filtered
      update_results(destinationNames)
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
    start_telescope_spinner()
  end

  opts.on_refresh = getConnectedDevices

  M.show("Select Device", cachedDeviceNames or {}, function(_, index)
    projectConfig.settings.destination = results[index].id
    projectConfig.settings.platform = results[index].platform
    projectConfig.settings.deviceName = results[index].name
    projectConfig.settings.os = results[index].os
    projectConfig.save_settings()
    util.call(callback, results[index])
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
    vim.fn.jobstart("qlmanage -p '" .. selectedFile .. "'", {
      detach = true,
      on_exit = function() end,
    })

    -- HACK: the preview stays behind the terminal window
    -- when Neovim is running in tmux.
    if vim.env.TERM_PROGRAM == "tmux" then
      vim.defer_fn(function()
        util.shell("open -a qlmanage 2>/dev/null")
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
  elseif projectConfig.is_project_configured() then
    pickerActions.show_xcode_project_actions()
  elseif projectConfig.is_spm_configured() then
    pickerActions.show_spm_actions()
  end
end

return M
