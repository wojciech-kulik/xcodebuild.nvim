local notifications = require("xcodebuild.notifications")
local util = require("xcodebuild.util")
local projectConfig = require("xcodebuild.project_config")
local xcode = require("xcodebuild.xcode")
local projectBuilder = require("xcodebuild.project_builder")
local simulator = require("xcodebuild.simulator")
local actions = require("xcodebuild.actions")

local M = {}

function M.start_dap_in_swift_buffer()
  local loadedDap, dap = pcall(require, "dap")
  if not loadedDap then
    error("Could not load nvim-dap plugin")
    return
  end

  local windows = vim.api.nvim_list_wins()

  for _, winid in ipairs(windows) do
    local bufnr = vim.api.nvim_win_get_buf(winid)
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    local extension = string.match(bufname, "%.(%a+)$")

    if extension and extension:lower() == "swift" then
      vim.api.nvim_win_call(winid, function()
        dap.continue()
      end)

      return
    end
  end

  error("Could not find a Swift buffer to start the debugger")
end

function M.build_and_debug(callback)
  local loadedDap, dap = pcall(require, "dap")
  if not loadedDap then
    notifications.send_error("Could not load nvim-dap plugin")
    return
  end

  xcode.kill_app(projectConfig.settings.productName)
  M.start_dap_in_swift_buffer()

  projectBuilder.build_project({}, function(report)
    local success = util.is_empty(report.buildErrors)

    if success then
      simulator.run_app(false, callback)
    else
      dap.terminate()

      local loadedDapui, dapui = pcall(require, "dapui")
      if loadedDapui then
        dapui.close()
      end
    end
  end)
end

function M.debug_without_build(callback)
  xcode.kill_app(projectConfig.settings.productName)
  M.start_dap_in_swift_buffer()
  simulator.run_app(false, callback)
end

function M.attach_debugger_for_tests()
  local loadedDap, dap = pcall(require, "dap")
  if not loadedDap then
    notifications.send_error("Could not load nvim-dap plugin")
    return
  end

  local group = vim.api.nvim_create_augroup("XcodebuildAttachingDebugger", { clear = true })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "XcodebuildTestsStatus",
    once = true,
    callback = function()
      vim.api.nvim_del_augroup_by_id(group)
      M.start_dap_in_swift_buffer()
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "XcodebuildTestsFinished", "XcodebuildActionCancelled" },
    once = true,
    callback = function()
      vim.api.nvim_del_augroup_by_id(group)

      if dap.session() then
        dap.terminate()
      end
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "XcodebuildBuildFinished",
    once = true,
    callback = function(event)
      if not event.data.success then
        vim.api.nvim_del_augroup_by_id(group)
      end
    end,
  })
end

function M.debug_tests()
  actions.run_tests()
  M.attach_debugger_for_tests()
end

function M.debug_target_tests()
  actions.run_target_tests()
  M.attach_debugger_for_tests()
end

function M.debug_class_tests()
  actions.run_class_tests()
  M.attach_debugger_for_tests()
end

function M.debug_func_test()
  actions.run_func_test()
  M.attach_debugger_for_tests()
end

function M.debug_selected_tests()
  actions.run_selected_tests()
  M.attach_debugger_for_tests()
end

function M.debug_failing_tests()
  actions.run_failing_tests()
  M.attach_debugger_for_tests()
end

function M.get_program_path()
  if projectConfig.settings.platform == "macOS" then
    return projectConfig.settings.appPath .. "/Contents/MacOS/" .. projectConfig.settings.productName
  else
    return projectConfig.settings.appPath
  end
end

function M.wait_for_pid()
  local co = coroutine
  local productName = projectConfig.settings.productName

  if not productName then
    notifications.send_error("You must build the application first")
    return
  end

  return co.create(function(dap_run_co)
    local pid = nil

    notifications.send("Attaching debugger...")
    for _ = 1, 10 do
      util.shell("sleep 1")
      pid = xcode.get_app_pid(productName)

      if tonumber(pid) then
        break
      end
    end

    if not tonumber(pid) then
      notifications.send_error("Launching the application timed out")

      ---@diagnostic disable-next-line: deprecated
      co.close(dap_run_co)
    end

    co.resume(dap_run_co, pid)
  end)
end

function M.clear_console()
  local success, dapui = pcall(require, "dapui")
  if not success then
    return
  end

  local bufnr = dapui.elements.console.buffer()
  if not bufnr then
    return
  end

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
  vim.bo[bufnr].modified = false
  vim.bo[bufnr].modifiable = false
end

function M.update_console(output)
  local success, dapui = pcall(require, "dapui")
  if not success then
    return
  end

  local bufnr = dapui.elements.console.buffer()
  if not bufnr then
    return
  end

  if util.is_empty(output) then
    return
  end

  vim.bo[bufnr].modifiable = true

  local autoscroll = false
  local winnr = vim.fn.win_findbuf(bufnr)[1]
  if winnr then
    local currentWinnr = vim.api.nvim_get_current_win()
    local lastLine = vim.api.nvim_buf_line_count(bufnr)
    local currentLine = vim.api.nvim_win_get_cursor(winnr)[1]
    autoscroll = currentWinnr ~= winnr or currentLine == lastLine
  end

  vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, output)

  if autoscroll then
    vim.api.nvim_win_call(winnr, function()
      vim.cmd("normal! G")
    end)
  end

  vim.bo[bufnr].modified = false
  vim.bo[bufnr].modifiable = false
end

return M
