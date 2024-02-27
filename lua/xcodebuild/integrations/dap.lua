---@mod xcodebuild.integrations.dap DAP Integration
---@tag xcodebuild.dap
---@brief [[
---This module is responsible for the integration with `nvim-dap` plugin.
---
---It provides functions to start the debugger and to manage its state.
---
---To configure `nvim-dap` for development:
---
---  1. Download codelldb VS Code plugin from: https://github.com/vadimcn/codelldb/releases
---     For macOS use darwin version. Just unzip vsix file and set paths below.
---  2. Install also `nvim-dap-ui` for a nice GUI to debug.
---  3. Make sure to enable console window from `nvim-dap-ui` to see simulator logs.
---
---Sample `nvim-dap` configuration:
--->lua
---    return {
---      "mfussenegger/nvim-dap",
---      dependencies = {
---        "wojciech-kulik/xcodebuild.nvim"
---      },
---      config = function()
---        local dap = require("dap")
---        local xcodebuild = require("xcodebuild.integrations.dap")
---
---        dap.configurations.swift = {
---          {
---            name = "iOS App Debugger",
---            type = "codelldb",
---            request = "attach",
---            program = xcodebuild.get_program_path,
---            cwd = "${workspaceFolder}",
---            stopOnEntry = false,
---            waitFor = true,
---          },
---        }
---
---        dap.adapters.codelldb = {
---          type = "server",
---          port = "13000",
---          executable = {
---            -- set path to the downloaded codelldb
---            -- sample path: "/Users/YOU/Downloads/codelldb-aarch64-darwin/extension/adapter/codelldb"
---            command = "/path/to/codelldb/extension/adapter/codelldb",
---            args = {
---              "--port",
---              "13000",
---              "--liblldb",
---              -- make sure that this path is correct on your side
---              "/Applications/Xcode.app/Contents/SharedFrameworks/LLDB.framework/Versions/A/LLDB",
---            },
---          },
---        }
---
---        -- disables annoying warning that requires hitting enter
---        local orig_notify = require("dap.utils").notify
---        require("dap.utils").notify = function(msg, log_level)
---          if not string.find(msg, "Either the adapter is slow") then
---            orig_notify(msg, log_level)
---          end
---        end
---
---        -- sample keymaps to debug application
---        vim.keymap.set("n", "<leader>dd", xcodebuild.build_and_debug, { desc = "Build & Debug" })
---        vim.keymap.set("n", "<leader>dr", xcodebuild.debug_without_build, { desc = "Debug Without Building" })
---        vim.keymap.set("n", "<leader>dt", xcodebuild.debug_tests, { desc = "Debug Tests" })
---
---        -- you can also debug smaller scope tests:
---        -- debug_target_tests, debug_class_tests, debug_func_test,
---        -- debug_selected_tests, debug_failing_tests
---      end,
---    }
---<
---
---See:
---  https://github.com/mfussenegger/nvim-dap
---  https://github.com/rcarriga/nvim-dap-ui
---  https://github.com/vadimcn/codelldb
---
---@brief ]]

local util = require("xcodebuild.util")
local helpers = require("xcodebuild.helpers")
local constants = require("xcodebuild.core.constants")
local notifications = require("xcodebuild.broadcasting.notifications")
local projectConfig = require("xcodebuild.project.config")
local device = require("xcodebuild.platform.device")
local actions = require("xcodebuild.actions")
local remoteDebugger = require("xcodebuild.integrations.remote_debugger")

local M = {}

---Checks if the project is configured.
---If not, it sends an error notification.
---@return boolean
local function validate_project()
  if not projectConfig.is_project_configured() then
    notifications.send_error("The project is missing some details. Please run XcodebuildSetup first.")
    return false
  end

  return true
end

---Sets the remote debugger mode based on the OS version.
local function set_remote_debugger_mode()
  local majorVersion = helpers.get_major_os_version()

  if majorVersion and majorVersion < 17 then
    remoteDebugger.set_mode(remoteDebugger.LEGACY_MODE)
  else
    remoteDebugger.set_mode(remoteDebugger.SECURED_MODE)
  end
end

---Starts `nvim-dap` debug session. It connects to `codelldb`.
local function start_dap()
  local loadedDap, dap = pcall(require, "dap")
  if not loadedDap then
    error("xcodebuild.nvim: Could not load nvim-dap plugin")
    return
  end

  dap.run(dap.configurations.swift[1])
end

---Builds, installs and runs the project. Also, it starts the debugger.
---@param callback function|nil
function M.build_and_debug(callback)
  local loadedDap, dap = pcall(require, "dap")
  if not loadedDap then
    notifications.send_error("Could not load nvim-dap plugin")
    return
  end

  if not validate_project() then
    return
  end

  local remote = projectConfig.settings.platform == constants.Platform.IOS_PHYSICAL_DEVICE

  if not remote then
    device.kill_app()
    start_dap()
  end

  local projectBuilder = require("xcodebuild.project.builder")

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
        set_remote_debugger_mode()
        remoteDebugger.start_remote_debugger(callback)
      end)
    else
      device.run_app(false, callback)
    end
  end)
end

---It only installs the app and starts the debugger without building
---the project.
---@param callback function|nil
function M.debug_without_build(callback)
  if not validate_project() then
    return
  end

  local remote = projectConfig.settings.platform == constants.Platform.IOS_PHYSICAL_DEVICE

  if remote then
    device.install_app(function()
      set_remote_debugger_mode()
      remoteDebugger.start_remote_debugger(callback)
    end)
  else
    device.kill_app()
    start_dap()
    device.run_app(true, callback)
  end
end

---Attaches the debugger to the running application when tests are starting.
---
---Tests are controlled by `xcodebuild` tool, so we can't request waiting
---for the debugger to attach. Instead, we listen to the
---`XcodebuildTestsStatus` to start the debugger.
---
---When `XcodebuildTestsFinished` or `XcodebuildActionCancelled` is received,
---we terminate the debugger session.
---If build failed, we stop waiting for events.
function M.attach_debugger_for_tests()
  local loadedDap, dap = pcall(require, "dap")
  if not loadedDap then
    notifications.send_error("Could not load nvim-dap plugin")
    return
  end

  if projectConfig.settings.platform == constants.Platform.IOS_PHYSICAL_DEVICE then
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
      start_dap()
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

---Starts the debugger and runs all tests.
function M.debug_tests()
  actions.run_tests()
  M.attach_debugger_for_tests()
end

---Starts the debugger and runs all tests in the target.
function M.debug_target_tests()
  actions.run_target_tests()
  M.attach_debugger_for_tests()
end

---Starts the debugger and runs all tests in the class.
function M.debug_class_tests()
  actions.run_class_tests()
  M.attach_debugger_for_tests()
end

---Starts the debugger and runs the current test.
function M.debug_func_test()
  actions.run_func_test()
  M.attach_debugger_for_tests()
end

---Starts the debugger and runs the selected tests.
function M.debug_selected_tests()
  actions.run_selected_tests()
  M.attach_debugger_for_tests()
end

---Starts the debugger and re-runs the failing tests.
function M.debug_failing_tests()
  actions.run_failing_tests()
  M.attach_debugger_for_tests()
end

---Returns path to the built application.
---@return string
function M.get_program_path()
  if projectConfig.settings.platform == constants.Platform.MACOS then
    return projectConfig.settings.appPath .. "/Contents/MacOS/" .. projectConfig.settings.productName
  else
    return projectConfig.settings.appPath
  end
end

---Waits for the application to start and returns its PID.
---@return thread|nil # coroutine with pid
function M.wait_for_pid()
  local co = coroutine
  local productName = projectConfig.settings.productName
  local xcode = require("xcodebuild.core.xcode")

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

---Clears the DAP console buffer.
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

---Updates the DAP console buffer with the given output.
---It also automatically scrolls to the last line if
---the cursor is in a different window or if the cursor
---is not on the last line.
---@param output string[]
---@param append boolean|nil # if true, appends the output to the last line
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
