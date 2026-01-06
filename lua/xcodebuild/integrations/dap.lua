---@mod xcodebuild.integrations.dap DAP Integration
---@tag xcodebuild.dap
---@brief [[
---This module is responsible for the integration with `nvim-dap` plugin.
---
---It provides functions to start the debugger and to manage its state.
---
---To configure `nvim-dap` for development:
---
---  1. [Only for Xcode versions below 16]
---     - Download `codelldb` VS Code plugin from: https://github.com/vadimcn/codelldb/releases
---     - For macOS use Darwin version and unzip `vsix` file.
---     - Update `codelldb` integration config (node: `integrations.codelldb`).
---  2. Install `nvim-dap-ui` for a nice GUI to debug.
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
---        local xcodebuild = require("xcodebuild.integrations.dap")
---        xcodebuild.setup()
---
---        vim.keymap.set("n", "<leader>dd", xcodebuild.build_and_debug, { desc = "Build & Debug" })
---        vim.keymap.set("n", "<leader>dr", xcodebuild.debug_without_build, { desc = "Debug Without Building" })
---        vim.keymap.set("n", "<leader>dt", xcodebuild.debug_tests, { desc = "Debug Tests" })
---        vim.keymap.set("n", "<leader>dT", xcodebuild.debug_class_tests, { desc = "Debug Class Tests" })
---        vim.keymap.set("n", "<leader>b", xcodebuild.toggle_breakpoint, { desc = "Toggle Breakpoint" })
---        vim.keymap.set("n", "<leader>B", xcodebuild.toggle_message_breakpoint, { desc = "Toggle Message Breakpoint" })
---        vim.keymap.set("n", "<leader>dx", xcodebuild.terminate_session, { desc = "Terminate Debugger" })
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
local dapSymbolicate = require("xcodebuild.integrations.dap-symbolicate")
local debugger = require("xcodebuild.platform.debugger")

local PLUGIN_ID = "xcodebuild.nvim"

local M = {}

---Sets the remote debugger mode based on the OS version.
local function set_remote_debugger_mode()
  local isWatchOS = projectConfig.settings.platform == constants.Platform.WATCHOS_DEVICE
  local isVisionOS = projectConfig.settings.platform == constants.Platform.VISIONOS_DEVICE

  if isWatchOS or isVisionOS then
    remoteDebugger.set_mode(remoteDebugger.SECURED_MODE)
    remoteDebugger.set_secured_service("lockdown")
    return
  end

  -- iOS / iPadOS / tvOS

  local majorVersion = helpers.get_major_os_version()
  local minorVersion = helpers.get_minor_os_version()

  if majorVersion and majorVersion < 17 then
    remoteDebugger.set_mode(remoteDebugger.LEGACY_MODE)
  else
    remoteDebugger.set_mode(remoteDebugger.SECURED_MODE)
    majorVersion = majorVersion or 0
    minorVersion = minorVersion or 0

    if (majorVersion == 17 and minorVersion >= 4) or (majorVersion > 17) then
      remoteDebugger.set_secured_service("lockdown")
    else
      remoteDebugger.set_secured_service("remote")
    end
  end
end

---Gets dapui module if ready
---@return table|nil
local function get_dapui()
  local success, dapui = pcall(require, "dapui")

  if not success or not dapui or not dapui.elements or not dapui.elements.console then
    return nil
  end

  return dapui
end

---Starts `nvim-dap` debug session. It connects to `lldb`.
local function start_dap()
  local loadedDap, dap = pcall(require, "dap")
  if not loadedDap then
    error("xcodebuild.nvim: Could not load nvim-dap plugin")
    return
  end

  dapSymbolicate.dap_started()
  dap.run(dap.configurations.swift[1])
end

---Stops the current `nvim-dap` session.
local function stop_session()
  local loadedDap, dap = pcall(require, "dap")
  if not loadedDap then
    return
  end

  if dap.session() then
    dap.terminate()
  end
end

---Disconnects the current `nvim-dap` session.
local function disconnect_session()
  local loadedDap, dap = pcall(require, "dap")
  if not loadedDap then
    return
  end

  if not dap.session() then
    return
  end

  local isDevice = constants.is_device(projectConfig.settings.platform)
  if isDevice then
    dap.repl.execute("process detach")
    dap.disconnect()
  else
    dap.disconnect()
  end
end

---Detaches the debugger from the running application.
function M.detach_debugger()
  disconnect_session()
end

---Attaches the debugger to the running application.
---@param callback function|nil
function M.attach_and_debug(callback)
  local loadedDap, _ = pcall(require, "dap")
  if not loadedDap then
    notifications.send_error("Could not load nvim-dap plugin")
    return
  end

  if not helpers.validate_project({ requiresApp = true }) then
    return
  end

  stop_session()

  local xcode = require("xcodebuild.core.xcode")
  local isDevice = constants.is_device(projectConfig.settings.platform)
  local productName = projectConfig.settings.productName
  local pid

  if not productName then
    notifications.send_error("You must build the application first")
    return
  end

  if isDevice then
    pid = require("xcodebuild.platform.device_proxy").find_app_pid(productName)
  else
    pid = xcode.get_app_pid(productName, projectConfig.settings.platform)
  end

  if not pid or pid == "" then
    notifications.send_error("The application is not running. Could not attach the debugger.")
    return
  end

  if isDevice then
    set_remote_debugger_mode()
    remoteDebugger.start_remote_debugger({ attach = true }, callback)
  else
    start_dap()
  end
end

---Builds, installs and runs the project. Also, it starts the debugger.
---@param callback function|nil
function M.build_and_debug(callback)
  local loadedDap, _ = pcall(require, "dap")
  if not loadedDap then
    notifications.send_error("Could not load nvim-dap plugin")
    return
  end

  if not helpers.validate_project({ requiresApp = true }) then
    return
  end

  stop_session()

  local isMacOS = projectConfig.settings.platform == constants.Platform.MACOS
  local isSimulator = constants.is_simulator(projectConfig.settings.platform)
  local isDevice = constants.is_device(projectConfig.settings.platform)

  if isSimulator or isMacOS then
    device.kill_app()
  end

  local projectBuilder = require("xcodebuild.project.builder")

  projectBuilder.build_project({}, function(report)
    local success = util.is_empty(report.buildErrors)
    if not success then
      return
    end

    if isDevice then
      device.install_app(function()
        set_remote_debugger_mode()
        remoteDebugger.start_remote_debugger({}, callback)
      end)
    else
      device.run_app(true, function()
        -- macOS apps are launched via dap "launch" request. Otherwise, logs wouldn't be captured.
        -- iOS simulator apps we first launch, then attach debugger.
        if isSimulator then
          start_dap()
        end
        util.call(callback)
      end)
    end
  end)
end

---It only installs the app and starts the debugger without building
---the project.
---@param callback function|nil
function M.debug_without_build(callback)
  if not helpers.validate_project({ requiresApp = true }) then
    return
  end

  stop_session()

  local isSimulator = constants.is_simulator(projectConfig.settings.platform)
  local isDevice = constants.is_device(projectConfig.settings.platform)

  if isDevice then
    device.install_app(function()
      set_remote_debugger_mode()
      remoteDebugger.start_remote_debugger({}, callback)
    end)
  else
    device.kill_app()
    device.run_app(true, function()
      -- macOS apps are launched via dap "launch" request. Otherwise, logs wouldn't be captured.
      -- iOS simulator apps we first launch, then attach debugger.
      if isSimulator then
        start_dap()
      end
      util.call(callback)
    end)
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

  if constants.is_device(projectConfig.settings.platform) then
    notifications.send_error(
      "Debugging tests on physical devices is not supported. Please use the simulator."
    )
    return
  end

  if not helpers.validate_project({ requiresApp = true }) then
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
  actions.run_nearest_test()
  M.attach_debugger_for_tests()
end

---Starts the debugger and runs the selected tests.
function M.debug_selected_tests()
  actions.run_selected_tests()
  M.attach_debugger_for_tests()
end

---Starts the debugger and re-runs the failing tests.
function M.debug_failing_tests()
  actions.rerun_failed_tests()
  M.attach_debugger_for_tests()
end

---Clears the DAP console buffer.
---@param validate boolean|nil # if true, shows error if the buffer is a terminal
function M.clear_console(validate)
  local dapui = get_dapui()
  if not dapui then
    return
  end

  local bufnr = dapui.elements.console.buffer()
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  if vim.bo[bufnr].buftype == "terminal" then
    if validate then
      local isMacOS = projectConfig.settings.platform == constants.Platform.MACOS
      if isMacOS then
        notifications.send_error("Cannot clear DAP console while debugging macOS apps.")
      else
        notifications.send_error("Cannot clear DAP console when it's a terminal buffer.")
      end
    end

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
  local dapui = get_dapui()
  if not dapui then
    return
  end

  local bufnr = dapui.elements.console.buffer()
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  if util.is_empty(output) then
    return
  end

  dapSymbolicate.process_logs(output, function(symbolicated)
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, symbolicated)
    vim.bo[bufnr].modified = false
    vim.bo[bufnr].modifiable = false
  end)

  vim.bo[bufnr].modifiable = true

  local autoscroll = false
  local winnr = vim.fn.win_findbuf(bufnr)[1]
  if winnr then
    local currentWinnr = vim.api.nvim_get_current_win()
    local lastLine = vim.api.nvim_buf_line_count(bufnr)
    local currentLine = vim.api.nvim_win_get_cursor(winnr)[1]
    autoscroll = currentWinnr ~= winnr or currentLine == lastLine
  end

  if append and vim.api.nvim_buf_line_count(bufnr) > 1 then
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

---Reads breakpoints from the `.nvim/xcodebuild/breakpoints.json` file.
---Returns breakpoints or nil if the file is missing.
---@return table|nil
local function read_breakpoints()
  local breakpointsPath = require("xcodebuild.project.appdata").breakpoints_filepath
  local success, content = util.readfile(breakpointsPath)

  if not success or util.is_empty(content) then
    return nil
  end

  return vim.fn.json_decode(content)
end

---Saves breakpoints to `.nvim/xcodebuild/breakpoints.json` file.
function M.save_breakpoints()
  local breakpoints = read_breakpoints() or {}
  local breakpointsPerBuffer = require("dap.breakpoints").get()

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    breakpoints[vim.api.nvim_buf_get_name(bufnr)] = breakpointsPerBuffer[bufnr]
  end

  local breakpointsPath = require("xcodebuild.project.appdata").breakpoints_filepath
  local fp = io.open(breakpointsPath, "w")

  if fp then
    fp:write(vim.fn.json_encode(breakpoints))
    fp:close()
  end
end

---Loads breakpoints from `.nvim/xcodebuild/breakpoints.json` file and sets them
---in {bufnr} or in all loaded buffers if {bufnr} is nil.
---@param bufnr number|nil
function M.load_breakpoints(bufnr)
  local breakpoints = read_breakpoints()
  if not breakpoints then
    return
  end

  local buffers = bufnr and { bufnr } or vim.api.nvim_list_bufs()

  for _, buf in ipairs(buffers) do
    local fileName = vim.api.nvim_buf_get_name(buf)

    if breakpoints[fileName] then
      for _, bp in pairs(breakpoints[fileName]) do
        local opts = {
          condition = bp.condition,
          log_message = bp.logMessage,
          hit_condition = bp.hitCondition,
        }
        require("dap.breakpoints").set(opts, tonumber(buf), bp.line)
      end
    end
  end
end

---Toggles a breakpoint in the current line and saves breakpoints to disk.
function M.toggle_breakpoint()
  require("dap").toggle_breakpoint()
  M.save_breakpoints()
end

---Toggles a breakpoint with a log message in the current line and saves breakpoints to disk.
---To print a variable, wrap it with {}: `{myObject.myProperty}`.
function M.toggle_message_breakpoint()
  require("dap").set_breakpoint(nil, nil, vim.fn.input("Breakpoint message: "))
  M.save_breakpoints()
end

---Terminates the debugger session, cancels the current action, and closes the `nvim-dap-ui`.
function M.terminate_session()
  if require("dap").session() then
    require("dap").terminate()
  end

  require("xcodebuild.actions").cancel()

  local success, dapui = pcall(require, "dapui")
  if success then
    dapui.close()
  end
end

---Returns a list of actions with names for the `nvim-dap` plugin.
---@return table<{name:string,action:function}>
function M.get_actions()
  return {
    { name = "Build & Debug", action = M.build_and_debug },
    { name = "Debug Without Building", action = M.debug_without_build },
    { name = "Debug Tests", action = M.debug_tests },
    { name = "Debug Current Test Class", action = M.debug_class_tests },
    { name = "Attach Debugger", action = M.attach_and_debug },
    { name = "Detach Debugger", action = disconnect_session },
    {
      name = "Clear DAP Console",
      action = function()
        M.clear_console(true)
      end,
    },
  }
end

---Registers user commands for the `nvim-dap` plugin integration.
---Commands:
---  - `XcodebuildAttachDebugger` - starts the debugger session.
---  - `XcodebuildDetachDebugger` - disconnects the debugger session.
---  - `XcodebuildBuildDebug` - builds, installs, and runs the project with the debugger.
---  - `XcodebuildDebug` - installs and runs the project with the debugger.
function M.register_user_commands()
  -- stylua: ignore start
  vim.api.nvim_create_user_command("XcodebuildAttachDebugger", M.attach_and_debug, { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildDetachDebugger", M.detach_debugger, { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildBuildDebug", function() M.build_and_debug() end, { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildDebug", function() M.debug_without_build() end, { nargs = 0 })
  -- stylua: ignore end
end

---Sets up the adapter and configuration for the `nvim-dap` plugin.
---{loadBreakpoints} - if true or nil, sets up an autocmd to load breakpoints when a Swift file is opened.
---@param loadBreakpoints boolean|nil default: true
function M.setup(loadBreakpoints)
  if loadBreakpoints ~= nil and type(loadBreakpoints) ~= "boolean" then
    loadBreakpoints = true
    notifications.send_warning(
      "xcodebuild.nvim: invalid call to require('xcodebuild.integrations.dap').setup()\n"
        .. "This function now supports only one optional boolean parameter: loadBreakpoints (default: true).\n\n"
        .. "codelldb is no longer required for Xcode 16+. Please update your configuration to suppress this message.\n"
        .. "If you still need codelldb, please configure and enable `integrations.codelldb` in your config."
    )
  end

  local dap = require("dap")
  local codelldbConfig = require("xcodebuild.core.config").options.integrations.codelldb

  if codelldbConfig.enabled then
    debugger.set_implementation(require("xcodebuild.integrations.codelldb"))
  else
    debugger.set_implementation(require("xcodebuild.integrations.lldb"))
  end

  dap.configurations.swift = { debugger.get_ios_configuration() }
  dap.adapters[debugger.get_adapter_name()] = debugger.get_adapter()

  dap.defaults.fallback.exception_breakpoints = {}
  dap.listeners.after.event_process[PLUGIN_ID] = function()
    notifications.send("Debugger attached")
  end
  dap.listeners.after.event_exited[PLUGIN_ID] = function()
    notifications.send("Debugger disconnected")
  end

  M.register_user_commands()

  if loadBreakpoints ~= false then
    vim.api.nvim_create_autocmd({ "BufReadPost" }, {
      group = vim.api.nvim_create_augroup("xcodebuild-integrations-dap", { clear = true }),
      pattern = "*.swift",
      callback = function(event)
        M.load_breakpoints(event.buf)
      end,
    })
  end

  local orig_notify = require("dap.utils").notify
  require("dap.utils").notify = function(msg, log_level)
    if not string.find(msg, "Either the adapter is slow", 1, true) then
      orig_notify(msg, log_level)
    end
  end
end

return M
