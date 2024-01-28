local notifications = require("xcodebuild.notifications")
local coordinator = require("xcodebuild.coordinator")
local pickers = require("xcodebuild.pickers")
local logs = require("xcodebuild.logs")
local coverage = require("xcodebuild.coverage")
local testExplorer = require("xcodebuild.test_explorer")

local M = {}

local function defer_send(text)
  vim.defer_fn(function()
    notifications.send(text)
  end, 100)
end

local function update_settings(callback)
  defer_send("Updating project settings...")
  coordinator.update_settings(function()
    notifications.send("Project settings updated")

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

function M.build(callback)
  coordinator.cancel()
  coordinator.build_project({}, callback)
end

function M.clean_build(callback)
  coordinator.cancel()
  coordinator.build_project({ clean = true }, callback)
end

function M.build_for_testing(callback)
  coordinator.cancel()
  coordinator.build_project({ buildForTesting = true }, callback)
end

function M.cancel()
  coordinator.cancel()
  notifications.send("Stopped")
end

function M.configure_project()
  coordinator.cancel()
  coordinator.configure_project()
end

function M.build_and_run(callback)
  coordinator.cancel()
  coordinator.build_and_run_app(false, callback)
end

function M.run(callback)
  coordinator.cancel()
  coordinator.run_app(false, callback)
end

function M.run_tests()
  coordinator.cancel()
  coordinator.run_tests()
end

function M.run_target_tests()
  coordinator.cancel()
  coordinator.run_selected_tests({
    currentTarget = true,
  })
end

function M.run_class_tests()
  coordinator.cancel()
  coordinator.run_selected_tests({
    currentClass = true,
  })
end

function M.run_func_test()
  coordinator.cancel()
  coordinator.run_selected_tests({
    currentTest = true,
  })
end

function M.run_selected_tests()
  coordinator.cancel()
  coordinator.run_selected_tests({
    selectedTests = true,
  })
end

function M.run_failing_tests()
  coordinator.cancel()
  coordinator.run_selected_tests({
    failingTests = true,
  })
end

function M.select_project(callback)
  coordinator.cancel()
  pickers.select_project(function()
    pickers.select_xcodeproj_if_needed(function()
      update_settings(callback)
    end, { close_on_select = true })
  end, { close_on_select = true })
end

function M.select_scheme(callback)
  defer_send("Loading schemes...")
  coordinator.cancel()

  pickers.select_xcodeproj_if_needed(function()
    pickers.select_scheme(nil, function()
      update_settings(callback)
    end, { close_on_select = true })
  end, { close_on_select = true })
end

function M.select_config(callback)
  defer_send("Loading schemes...")
  coordinator.cancel()

  pickers.select_xcodeproj_if_needed(function()
    pickers.select_config(function()
      update_settings(callback)
    end, { close_on_select = true })
  end, { close_on_select = true })
end

function M.select_testplan(callback)
  defer_send("Loading test plans...")
  coordinator.cancel()
  pickers.select_testplan(callback, { close_on_select = true })
end

function M.select_device(callback)
  defer_send("Loading devices...")
  coordinator.cancel()
  pickers.select_destination(function()
    update_settings(callback)
  end, { close_on_select = true })
end

function M.show_current_config()
  coordinator.show_current_config()
end

function M.clean_derived_data()
  coordinator.clean_derived_data()
end

function M.uninstall(callback)
  coordinator.cancel()
  coordinator.uninstall_app(callback)
end

function M.boot_simulator(callback)
  coordinator.boot_simulator(callback)
end

function M.show_failing_snapshot_tests()
  coordinator.show_failing_snapshot_tests()
end

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

function M.show_test_explorer()
  testExplorer.show()
end

function M.hide_test_explorer()
  testExplorer.hide()
end

function M.toggle_test_explorer()
  testExplorer.toggle()
end

return M
