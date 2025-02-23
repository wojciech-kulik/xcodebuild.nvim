---@mod xcodebuild.ui.picker_actions Picker Actions
---@brief [[
---This module is responsible for preparing and showing actions for picker based on the project type.
---@brief ]]

local util = require("xcodebuild.util")
local config = require("xcodebuild.core.config").options
local snapshots = require("xcodebuild.tests.snapshots")

local M = {}

---Shows picker with actions.
---@param actionsNames string[]
---@param actionsPointers function[]
local function show_picker(actionsNames, actionsPointers)
  require("xcodebuild.ui.pickers").show("Xcodebuild Actions", actionsNames, function(_, index)
    local selectSchemeIndex = util.indexOf(actionsNames, "Select Scheme")

    if #actionsNames == 1 or index >= selectSchemeIndex then
      actionsPointers[index]()
    else
      vim.defer_fn(actionsPointers[index], 100)
    end
  end, { close_on_select = true })
end

---Adds test actions to the list of actions.
---@param actionsNames string[]
---@param actionsPointers function[]
local function add_test_actions(actionsNames, actionsPointers)
  local actions = require("xcodebuild.actions")
  local toggleLogsIndex = util.indexOf(actionsNames, "Toggle Logs") or 16

  if config.prepare_snapshot_test_previews then
    if util.is_not_empty(snapshots.get_failing_snapshots()) then
      table.insert(actionsNames, toggleLogsIndex, "Preview Failing Snapshot Tests")
      table.insert(actionsPointers, toggleLogsIndex, actions.show_failing_snapshot_tests)
    end
  end

  if config.code_coverage.enabled then
    if require("xcodebuild.code_coverage.report").is_report_available() then
      table.insert(actionsNames, toggleLogsIndex, "Show Code Coverage Report")
      table.insert(actionsPointers, toggleLogsIndex, actions.show_code_coverage_report)
      table.insert(actionsNames, toggleLogsIndex + 1, "Toggle Code Coverage")
      table.insert(actionsPointers, toggleLogsIndex + 1, actions.toggle_code_coverage)
    else
      table.insert(actionsNames, toggleLogsIndex, "Toggle Code Coverage")
      table.insert(actionsPointers, toggleLogsIndex, actions.toggle_code_coverage)
    end
  end

  if config.test_explorer.enabled then
    table.insert(actionsNames, toggleLogsIndex + 1, "Toggle Test Explorer")
    table.insert(actionsPointers, toggleLogsIndex + 1, actions.test_explorer_toggle)
  end
end

---Adds DAP actions to the list of actions.
---@param actionsNames string[]
---@param actionsPointers function[]
local function add_dap_actions(actionsNames, actionsPointers)
  local loadedDap, dap = pcall(require, "dap")
  local isDapConfigured = loadedDap and dap.configurations and util.is_not_empty(dap.configurations["swift"])

  if isDapConfigured then
    local dapIntegration = require("xcodebuild.integrations.dap")
    local dapActions = dapIntegration.get_actions()
    local counter = util.indexOf(actionsNames, "Cancel Running Action") or 6

    table.insert(dapActions, 1, { name = "---------------------------------", action = function() end })

    for _, action in ipairs(dapActions) do
      counter = counter + 1
      table.insert(actionsNames, counter, action.name)
      table.insert(actionsPointers, counter, action.action)
    end
  end
end

---Adds Previews actions to the list of actions.
---@param actionsNames string[]
---@param actionsPointers function[]
local function add_previews_actions(actionsNames, actionsPointers)
  local loadedSnacks, _ = pcall(require, "snacks")

  if loadedSnacks then
    local previews = require("xcodebuild.core.previews")
    local previewsActions = previews.get_actions()
    local counter = util.indexOf(actionsNames, "Repeat Last Test Run") or 6

    table.insert(previewsActions, 1, { name = "---------------------------------", action = function() end })

    for _, action in ipairs(previewsActions) do
      counter = counter + 1
      table.insert(actionsNames, counter, action.name)
      table.insert(actionsPointers, counter, action.action)
    end
  end
end

---Shows available actions for Swift Package project.
function M.show_spm_actions()
  local actions = require("xcodebuild.actions")
  local actionsNames = {
    "Build Project",
    "Build Project (Clean Build)",
    "Build For Testing",
    "Cancel Running Action",
    "---------------------------------",
    "Run All Tests",
    "Run Current Test Target",
    "Run Current Test Class",
    "Run Nearest Test",
    "Rerun Failed Tests",
    "Repeat Last Test Run",
    "---------------------------------",
    "Select Scheme",
    "Select Device",
    "---------------------------------",
    "Toggle Logs",
    "---------------------------------",
    "Show Current Configuration",
    "Show Configuration Wizard",
    "---------------------------------",
    "Boot Selected Simulator",
    "---------------------------------",
    "Clean DerivedData",
    "Open Project in Xcode",
  }
  local actionsPointers = {
    actions.build,
    actions.clean_build,
    actions.build_for_testing,
    actions.cancel,

    function() end,

    actions.run_tests,
    actions.run_target_tests,
    actions.run_class_tests,
    actions.run_nearest_test,
    actions.rerun_failed_tests,
    actions.repeat_last_test_run,

    function() end,

    actions.select_scheme,
    actions.select_device,

    function() end,

    actions.toggle_logs,

    function() end,

    actions.show_current_config,
    actions.configure_project,

    function() end,

    actions.boot_simulator,

    function() end,

    actions.clean_derived_data,
    actions.open_in_xcode,
  }

  add_test_actions(actionsNames, actionsPointers)
  show_picker(actionsNames, actionsPointers)
end

---Shows available actions for Xcode library project.
function M.show_library_project_actions()
  local actions = require("xcodebuild.actions")
  local actionsNames = {
    "Build Project",
    "Build Project (Clean Build)",
    "Build For Testing",
    "Cancel Running Action",
    "---------------------------------",
    "Run Current Test Plan (All Tests)",
    "Run Current Test Target",
    "Run Current Test Class",
    "Run Nearest Test",
    "Rerun Failed Tests",
    "Repeat Last Test Run",
    "---------------------------------",
    "Select Scheme",
    "Select Device",
    "Select Test Plan",
    "---------------------------------",
    "Toggle Logs",
    "---------------------------------",
    "Show Project Manager",
    "Show Assets Manager",
    "Show Current Configuration",
    "Show Configuration Wizard",
    "---------------------------------",
    "Boot Selected Simulator",
    "---------------------------------",
    "Clean DerivedData",
    "Open Project in Xcode",
  }
  local actionsPointers = {
    actions.build,
    actions.clean_build,
    actions.build_for_testing,
    actions.cancel,

    function() end,

    actions.run_tests,
    actions.run_target_tests,
    actions.run_class_tests,
    actions.run_nearest_test,
    actions.rerun_failed_tests,
    actions.repeat_last_test_run,

    function() end,

    actions.select_scheme,
    actions.select_device,
    actions.select_testplan,

    function() end,

    actions.toggle_logs,

    function() end,

    actions.show_project_manager_actions,
    actions.show_assets_manager,
    actions.show_current_config,
    actions.configure_project,

    function() end,

    actions.boot_simulator,

    function() end,

    actions.clean_derived_data,
    actions.open_in_xcode,
  }

  add_test_actions(actionsNames, actionsPointers)
  show_picker(actionsNames, actionsPointers)
end

---Shows available actions for Xcode project.
function M.show_xcode_project_actions()
  local actions = require("xcodebuild.actions")
  local actionsNames = {
    "Build Project",
    "Build Project (Clean Build)",
    "Build & Run Project",
    "Build For Testing",
    "Run Without Building",
    "Cancel Running Action",
    "---------------------------------",
    "Run Current Test Plan (All Tests)",
    "Run Current Test Target",
    "Run Current Test Class",
    "Run Nearest Test",
    "Rerun Failed Tests",
    "Repeat Last Test Run",
    "---------------------------------",
    "Select Scheme",
    "Select Device",
    "Select Test Plan",
    "---------------------------------",
    "Toggle Logs",
    "---------------------------------",
    "Show Project Manager",
    "Show Assets Manager",
    "Show Current Configuration",
    "Show Configuration Wizard",
    "Edit Environment Variables",
    "Edit Run Arguments",
    "---------------------------------",
    "Boot Selected Simulator",
    "Install Application",
    "Uninstall Application",
    "---------------------------------",
    "Clean DerivedData",
    "Open Project in Xcode",
  }
  local actionsPointers = {
    actions.build,
    actions.clean_build,
    actions.build_and_run,
    actions.build_for_testing,
    actions.run,
    actions.cancel,

    function() end,

    actions.run_tests,
    actions.run_target_tests,
    actions.run_class_tests,
    actions.run_nearest_test,
    actions.rerun_failed_tests,
    actions.repeat_last_test_run,

    function() end,

    actions.select_scheme,
    actions.select_device,
    actions.select_testplan,

    function() end,

    actions.toggle_logs,

    function() end,

    actions.show_project_manager_actions,
    actions.show_assets_manager,
    actions.show_current_config,
    actions.configure_project,
    actions.edit_env_vars,
    actions.edit_run_args,

    function() end,

    actions.boot_simulator,
    actions.install_app,
    actions.uninstall_app,

    function() end,

    actions.clean_derived_data,
    actions.open_in_xcode,
  }

  add_test_actions(actionsNames, actionsPointers)
  add_dap_actions(actionsNames, actionsPointers)
  add_previews_actions(actionsNames, actionsPointers)
  show_picker(actionsNames, actionsPointers)
end

return M
