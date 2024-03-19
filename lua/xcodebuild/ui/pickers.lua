---@mod xcodebuild.ui.pickers Pickers
---@tag xcodebuild.pickers
---@brief [[
---This module is responsible for showing pickers using Telescope.nvim.
---@brief ]]

---@class PickerOptions
---@field on_refresh function|nil
---@field multiselect boolean|nil
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
local function update_results(results)
  if currentJobId == nil then
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
-- `xcodeproj` file with the same name, it will be selected automatically.
---@param callback fun(xcodeproj: string)|nil
---@param opts PickerOptions|nil
function M.select_xcodeproj_if_needed(callback, opts)
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
  local sanitizedFiles = {}
  local filenames = {}
  local files = util.shell(
    "find '"
      .. vim.fn.getcwd()
      .. "' -maxdepth "
      .. maxdepth
      .. " -iname '*.xcodeproj'"
      .. " -not -path '*/.*'"
      .. " 2>/dev/null"
  )

  for _, file in ipairs(files) do
    if util.trim(file) ~= "" then
      table.insert(sanitizedFiles, file)
      table.insert(filenames, string.match(file, ".*%/([^/]*)$"))
    end
  end

  M.show("Select Project", filenames, function(_, index)
    local selectedFile = sanitizedFiles[index]

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
  local sanitizedFiles = {}
  local filenames = {}
  local files = util.shell(
    "find '"
      .. vim.fn.getcwd()
      .. "' \\( -iname '*.xcodeproj' -o -iname '*.xcworkspace' \\)"
      .. " -not -path '*/.*' -not -path '*xcodeproj/project.xcworkspace'"
      .. " -maxdepth "
      .. maxdepth
      .. " 2>/dev/null"
  )

  for _, file in ipairs(files) do
    if util.trim(file) ~= "" then
      table.insert(sanitizedFiles, file)
      table.insert(filenames, string.match(file, ".*%/([^/]*)$"))
    end
  end

  M.show("Select Main Xcworkspace or Xcodeproj", filenames, function(_, index)
    local projectFile = sanitizedFiles[index]
    local isWorkspace = util.has_suffix(projectFile, "xcworkspace")

    projectConfig.settings.xcodeproj = not isWorkspace and projectFile or nil
    projectConfig.settings.projectFile = projectFile
    projectConfig.settings.projectCommand = (isWorkspace and "-workspace '" or "-project '")
      .. projectFile
      .. "'"

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
  if not xcodeproj then
    notifications.send_error("Xcode project file not set")
    return
  end

  local schemes = xcode.find_schemes(xcodeproj)
  local names = util.select(schemes, function(scheme)
    return scheme.name
  end)

  if util.is_empty(names) then
    notifications.send_error("No schemes found")
    return
  end

  M.show("Select Scheme", names, function(value, _)
    projectConfig.settings.scheme = value
    projectConfig.save_settings()
    update_xcode_build_server_config()
    util.call(callback, value)
  end, opts)
end

---Shows a picker with the available test plans.
---@param callback fun(testPlan: string|nil)|nil
---@param opts PickerOptions|nil
---@return number|nil job id
function M.select_testplan(callback, opts)
  local projectCommand = projectConfig.settings.projectCommand
  local scheme = projectConfig.settings.scheme

  if not projectCommand or not scheme then
    notifications.send_error("Project command and/or scheme not set")
    return nil
  end

  start_telescope_spinner()
  M.show("Select Test Plan", {}, function(value, _)
    projectConfig.settings.testPlan = value
    projectConfig.save_settings()
    events.project_settings_updated(projectConfig.settings)
    util.call(callback, value)
  end, opts)

  currentJobId = xcode.get_testplans(projectCommand, scheme, function(testPlans)
    if currentJobId and util.is_empty(testPlans) then
      vim.defer_fn(function()
        notifications.send_warning("Could not detect test plans")
      end, 100)

      if activePicker and util.is_not_empty(vim.fn.win_findbuf(activePicker.prompt_bufnr)) then
        telescopeActions.close(activePicker.prompt_bufnr)
      end

      util.call(callback)
    else
      update_results(testPlans)
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
  local scheme = projectConfig.settings.scheme
  local results = cachedDestinations or {}
  local useCache = config.commands.cache_devices
  local hasCachedDevices = useCache and util.is_not_empty(results) and util.is_not_empty(cachedDeviceNames)

  if not projectCommand or not scheme then
    notifications.send_error("Project command and/or scheme not set")
    return nil
  end

  local refreshDevices = function(connectedDevices)
    currentJobId = xcode.get_destinations(projectCommand, scheme, function(destinations)
      -- Don't show connected devices if the project is not configured for mobile devices
      local isForMobileDevices = vim.tbl_contains(destinations, function(destination)
        return destination.platform == constants.Platform.IOS_SIMULATOR
          or destination.platform == constants.Platform.IOS_PHYSICAL_DEVICE
      end, { predicate = true })

      if isForMobileDevices then
        for _, device in ipairs(connectedDevices) do
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

        if table.platform and table.platform == constants.Platform.IOS_PHYSICAL_DEVICE then
          return util.trim(name) .. (table.os and " (" .. table.os .. ")" or "")
        end

        if table.platform and table.platform ~= constants.Platform.IOS_SIMULATOR then
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
    if not deviceProxy.is_installed() then
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
  end)
end

---Shows a picker with the available actions.
---If the project is not configured, it will show the configuration wizard.
function M.show_all_actions()
  local actions = require("xcodebuild.actions")
  local actionsNames = {
    "Build Project",
    "Build Project (Clean Build)",
    "Build & Run Project",
    "Build For Testing",
    "Run Without Building",
    "Cancel Running Action",

    "Run Test Plan (All Tests)",
    "Run This Test Target",
    "Run This Test Class",
    "Run This Test",
    "Run Selected Tests",
    "Run Failed Tests",

    "Select Scheme",
    "Select Device",
    "Select Test Plan",

    "Toggle Logs",
    "Show Project Manager",
    "Show Current Configuration",
    "Show Configuration Wizard",
    "Boot Selected Simulator",
    "Clean DerivedData",
    "Install Application",
    "Uninstall Application",
    "Open Project in Xcode",
  }
  local actionsPointers = {
    actions.build,
    actions.clean_build,
    actions.build_and_run,
    actions.build_for_testing,
    actions.run,
    actions.cancel,

    actions.run_tests,
    actions.run_target_tests,
    actions.run_class_tests,
    actions.run_func_test,
    actions.run_selected_tests,
    actions.run_failing_tests,

    actions.select_scheme,
    actions.select_device,
    actions.select_testplan,

    actions.toggle_logs,
    actions.show_project_manager_actions,
    actions.show_current_config,
    actions.configure_project,
    actions.boot_simulator,
    actions.clean_derived_data,
    actions.install_app,
    actions.uninstall_app,
    actions.open_in_xcode,
  }

  if not projectConfig.is_project_configured() then
    actionsNames = { "Show Configuration Wizard" }
    actionsPointers = { actions.configure_project }
  end

  if config.prepare_snapshot_test_previews then
    if util.is_not_empty(snapshots.get_failing_snapshots()) then
      table.insert(actionsNames, 13, "Preview Failing Snapshot Tests")
      table.insert(actionsPointers, 13, actions.show_failing_snapshot_tests)
    end
  end

  if config.code_coverage.enabled then
    table.insert(actionsNames, 13, "Toggle Code Coverage")
    table.insert(actionsPointers, 13, actions.toggle_code_coverage)

    if require("xcodebuild.code_coverage.report").is_report_available() then
      table.insert(actionsNames, 14, "Show Code Coverage Report")
      table.insert(actionsPointers, 14, actions.show_code_coverage_report)
    end
  end

  if config.test_explorer.enabled then
    local row = util.indexOf(actionsNames, "Toggle Logs")
    if row then
      table.insert(actionsNames, row + 1, "Toggle Test Explorer")
      table.insert(actionsPointers, row + 1, actions.test_explorer_toggle)
    end
  end

  M.show("Xcodebuild Actions", actionsNames, function(_, index)
    if index > 12 or #actionsNames == 1 then
      actionsPointers[index]()
    else
      vim.defer_fn(actionsPointers[index], 100)
    end
  end, { close_on_select = true })
end

return M
