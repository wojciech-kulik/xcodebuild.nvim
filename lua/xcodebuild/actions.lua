local notifications = require("xcodebuild.notifications")
local coordinator = require("xcodebuild.coordinator")
local pickers = require("xcodebuild.pickers")
local logs = require("xcodebuild.logs")

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
  coordinator.build_project(false, callback)
end

function M.cancel()
  coordinator.cancel()
end

function M.configure_project()
  coordinator.configure_project()
end

function M.build_and_run(callback)
  coordinator.build_and_run_app(callback)
end

function M.run(callback)
  coordinator.run_app(callback)
end

function M.run_tests()
  coordinator.run_tests()
end

function M.run_class_tests()
  coordinator.run_selected_tests({
    currentClass = true,
  })
end

function M.run_func_test()
  coordinator.run_selected_tests({
    currentTest = true,
  })
end

function M.run_selected_tests()
  coordinator.run_selected_tests({
    selectedTests = true,
  })
end

function M.run_failing_tests()
  coordinator.run_selected_tests({
    failingTests = true,
  })
end

function M.select_project(callback)
  pickers.select_project(function()
    update_settings(callback)
  end, { close_on_select = true })
end

function M.select_scheme(callback)
  defer_send("Loading schemes...")
  pickers.select_scheme(nil, function()
    update_settings(callback)
  end, { close_on_select = true })
end

function M.select_config(callback)
  defer_send("Loading schemes...")
  pickers.select_config(function()
    update_settings(callback)
  end, { close_on_select = true })
end

function M.select_testplan(callback)
  defer_send("Loading test plans...")
  pickers.select_testplan(callback, { close_on_select = true })
end

function M.select_device(callback)
  defer_send("Loading devices...")
  pickers.select_destination(function()
    update_settings(callback)
  end, { close_on_select = true })
end

function M.show_current_config()
  coordinator.show_current_config()
end

function M.uninstall(callback)
  coordinator.uninstall_app(callback)
end

return M
