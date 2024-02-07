local notifications = require("xcodebuild.notifications")
local pickers = require("xcodebuild.pickers")
local logs = require("xcodebuild.logs")
local coverage = require("xcodebuild.coverage")
local testExplorer = require("xcodebuild.test_explorer")
local events = require("xcodebuild.events")
local simulator = require("xcodebuild.simulator")
local projectBuilder = require("xcodebuild.project_builder")
local testRunner = require("xcodebuild.test_runner")
local projectConfig = require("xcodebuild.project_config")
local helpers = require("xcodebuild.helpers")
local projectManager = require("xcodebuild.project_manager")

local M = {}

local function defer_send(text)
  vim.defer_fn(function()
    notifications.send(text)
  end, 100)
end

local function update_settings(callback)
  defer_send("Updating project settings...")
  projectConfig.update_settings(function()
    notifications.send("Project settings updated")
    events.project_settings_updated(require("xcodebuild.project_config").settings)

    if callback then
      callback()
    end
  end)
end

function M.open_logs()
  logs.open_logs(false)
end

function M.close_logs()
  logs.close_logs()
end

function M.toggle_logs()
  logs.toggle_logs()
end

function M.show_picker()
  pickers.show_all_actions()
end

function M.cancel()
  helpers.cancel_actions()
  notifications.send("Stopped")
end

function M.configure_project()
  helpers.cancel_actions()
  projectConfig.configure_project()
end

function M.build(callback)
  helpers.cancel_actions()
  projectBuilder.build_project({}, callback)
end

function M.clean_build(callback)
  helpers.cancel_actions()
  projectBuilder.build_project({ clean = true }, callback)
end

function M.build_for_testing(callback)
  helpers.cancel_actions()
  projectBuilder.build_project({ buildForTesting = true }, callback)
end

function M.build_and_run(callback)
  helpers.cancel_actions()
  projectBuilder.build_and_run_app(false, callback)
end

function M.clean_derived_data()
  projectBuilder.clean_derived_data()
end

function M.run(callback)
  helpers.cancel_actions()
  simulator.run_app(false, callback)
end

function M.run_tests()
  helpers.cancel_actions()
  testRunner.run_tests()
end

function M.run_target_tests()
  helpers.cancel_actions()
  testRunner.run_selected_tests({ currentTarget = true })
end

function M.run_class_tests()
  helpers.cancel_actions()
  testRunner.run_selected_tests({ currentClass = true })
end

function M.run_func_test()
  helpers.cancel_actions()
  testRunner.run_selected_tests({ currentTest = true })
end

function M.run_selected_tests()
  helpers.cancel_actions()
  testRunner.run_selected_tests({ selectedTests = true })
end

function M.run_failing_tests()
  helpers.cancel_actions()
  testRunner.run_selected_tests({ failingTests = true })
end

function M.show_failing_snapshot_tests()
  testRunner.show_failing_snapshot_tests()
end

function M.select_project(callback)
  helpers.cancel_actions()
  pickers.select_project(function()
    pickers.select_xcodeproj_if_needed(function()
      update_settings(callback)
    end, { close_on_select = true })
  end, { close_on_select = true })
end

function M.select_scheme(callback)
  defer_send("Loading schemes...")
  helpers.cancel_actions()

  pickers.select_xcodeproj_if_needed(function()
    pickers.select_scheme(nil, function()
      update_settings(callback)
    end, { close_on_select = true })
  end, { close_on_select = true })
end

function M.select_config(callback)
  defer_send("Loading schemes...")
  helpers.cancel_actions()

  pickers.select_xcodeproj_if_needed(function()
    pickers.select_config(function()
      update_settings(callback)
    end, { close_on_select = true })
  end, { close_on_select = true })
end

function M.select_testplan(callback)
  defer_send("Loading test plans...")
  helpers.cancel_actions()
  pickers.select_testplan(callback, { close_on_select = true })
end

function M.select_device(callback)
  defer_send("Loading devices...")
  helpers.cancel_actions()
  pickers.select_destination(function()
    update_settings(callback)
  end, { close_on_select = true })
end

function M.show_current_config()
  if not helpers.validate_project() then
    return
  end

  vim.defer_fn(function()
    notifications.send_project_settings(projectConfig.settings)
  end, 100)
end

function M.uninstall(callback)
  helpers.cancel_actions()
  simulator.uninstall_app(callback)
end

function M.boot_simulator(callback)
  simulator.boot_simulator(callback)
end

-- Code Coverage

function M.toggle_code_coverage(isVisible)
  coverage.toggle_code_coverage(isVisible)
end

function M.show_code_coverage_report()
  coverage.show_report()
end

function M.jump_to_next_coverage()
  coverage.jump_to_next_coverage()
end

function M.jump_to_previous_coverage()
  coverage.jump_to_previous_coverage()
end

-- Test Explorer

function M.test_explorer_show()
  testExplorer.show()
end

function M.test_explorer_hide()
  testExplorer.hide()
end

function M.test_explorer_toggle()
  testExplorer.toggle()
end

function M.test_explorer_run_selected_tests()
  testExplorer.run_selected_tests()
end

function M.test_explorer_rerun_tests()
  testExplorer.repeat_last_run()
end

-- Project Management

function M.create_new_file()
  projectManager.create_new_file()
end

function M.add_current_file()
  projectManager.add_current_file()
end

function M.rename_current_file()
  projectManager.rename_current_file()
end

function M.delete_current_file()
  projectManager.delete_current_file()
end

function M.create_new_group()
  projectManager.create_new_group()
end

function M.add_current_group()
  projectManager.add_current_group()
end

function M.rename_current_group()
  projectManager.rename_current_group()
end

function M.delete_current_group()
  projectManager.delete_current_group()
end

function M.show_current_file_targets()
  projectManager.show_current_file_targets()
end

function M.update_current_file_targets()
  projectManager.update_current_file_targets()
end

function M.show_project_manager_actions()
  projectManager.show_action_picker()
end

return M
