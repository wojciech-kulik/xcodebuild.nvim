local notifications = require("xcodebuild.broadcasting.notifications")
local helpers = require("xcodebuild.helpers")
local util = require("xcodebuild.util")
local projectConfig = require("xcodebuild.project.config")
local xcode = require("xcodebuild.core.xcode")
local projectBuilder = require("xcodebuild.project.builder")
local device = require("xcodebuild.platform.device")
local actions = require("xcodebuild.actions")

local M = {}

local function validate_project()
  if not projectConfig.is_project_configured() then
    notifications.send_error("The project is missing some details. Please run XcodebuildSetup first.")
    return false
  end

  return true
end

local function remote_debugger_start_dap()
  local remoteDebuggerLegacy = require("xcodebuild.integrations.remote_debugger_legacy")
  local remoteDebugger = require("xcodebuild.integrations.remote_debugger")
  local majorVersion = helpers.get_major_os_version()

  if majorVersion and majorVersion < 17 then
    remoteDebuggerLegacy.start_dap()
  else
    remoteDebugger.start_dap()
  end
end

local function remote_debugger_start(callback)
  local remoteDebuggerLegacy = require("xcodebuild.integrations.remote_debugger_legacy")
  local remoteDebugger = require("xcodebuild.integrations.remote_debugger")
  local majorVersion = helpers.get_major_os_version()

  if majorVersion and majorVersion < 17 then
    remoteDebuggerLegacy.start_remote_debugger(callback)
  else
    remoteDebugger.start_remote_debugger(callback)
  end
end

function M.start_dap_in_swift_buffer(remote)
  local loadedDap, dap = pcall(require, "dap")
  if not loadedDap then
    error("xcodebuild.nvim: Could not load nvim-dap plugin")
    return
  end

  local windows = vim.api.nvim_list_wins()

  for _, winid in ipairs(windows) do
    local bufnr = vim.api.nvim_win_get_buf(winid)
    local bufname = vim.api.nvim_buf_get_name(bufnr)
    local extension = string.match(bufname, "%.(%a+)$")

    if extension and extension:lower() == "swift" then
      vim.api.nvim_win_call(winid, function()
        if remote then
          remote_debugger_start_dap()
        else
          dap.continue()
        end
      end)

      return
    end
  end

  error("xcodebuild.nvim: Could not find a Swift buffer to start the debugger")
end

function M.build_and_debug(callback)
  local loadedDap, dap = pcall(require, "dap")
  if not loadedDap then
    notifications.send_error("Could not load nvim-dap plugin")
    return
  end

  if not validate_project() then
    return
  end

  local remote = projectConfig.settings.platform == "iOS"

  if not remote then
    device.kill_app()
    M.start_dap_in_swift_buffer()
  end

  projectBuilder.build_project({}, function(report)
    local success = util.is_empty(report.buildErrors)
    if not success then
      if dap.session() then
        dap.terminate()
      end

      local loadedDapui, dapui = pcall(require, "dapui")
      if loadedDapui then
        dapui.close()
      end
      return
    end

    if remote then
      device.install_app(function()
        remote_debugger_start(callback)
      end)
    else
      device.run_app(false, callback)
    end
  end)
end

function M.debug_without_build(callback)
  if not validate_project() then
    return
  end

  local remote = projectConfig.settings.platform == "iOS"

  if remote then
    device.install_app(function()
      remote_debugger_start(callback)
    end)
  else
    device.kill_app()
    M.start_dap_in_swift_buffer()
    device.run_app(true, callback)
  end
end

function M.attach_debugger_for_tests()
  local loadedDap, dap = pcall(require, "dap")
  if not loadedDap then
    notifications.send_error("Could not load nvim-dap plugin")
    return
  end

  if projectConfig.settings.platform == "iOS" then
    notifications.send_error(
      "Debugging tests on physical devices is not supported. Please use the simulator."
    )
    return
  end

  if not validate_project() then
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

function M.update_console(output, append)
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

  if append then
    local lastLine = vim.api.nvim_buf_get_lines(bufnr, -2, -1, false)[1]
    output[1] = lastLine .. output[1]
    vim.api.nvim_buf_set_lines(bufnr, -2, -1, false, output)
  else
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, output)
  end

  if autoscroll then
    vim.api.nvim_win_call(winnr, function()
      vim.cmd("normal! G")
    end)
  end

  vim.bo[bufnr].modified = false
  vim.bo[bufnr].modifiable = false
end

return M
