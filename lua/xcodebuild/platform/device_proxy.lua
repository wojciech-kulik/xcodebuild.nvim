---@mod xcodebuild.platform.device_proxy Device Proxy
---@brief [[
---This module contains the functionality to interact with physical devices
---using the `pymobiledevice3` tool.
---
---It allows to install, uninstall, run, kill applications, list connected
---devices, and start the debugger.
---
---This module is used for interactions with physical devices with iOS
---below version 17 and with all physical devices to start debugger.
---For other devices, the |xcodebuild.core.xcode| module is used.
---
---The tool can be installed by:
--->bash
---    python3 -m pip install -U pymobiledevice
---<
---
---See:
---  https://github.com/wojciech-kulik/xcodebuild.nvim/wiki/Features#-availability
---  https://github.com/wojciech-kulik/xcodebuild.nvim/wiki/Integrations#-debugging-on-ios-17
---  https://github.com/doronz88/pymobiledevice3
---@brief ]]

local util = require("xcodebuild.util")
local helpers = require("xcodebuild.helpers")
local constants = require("xcodebuild.core.constants")
local notifications = require("xcodebuild.broadcasting.notifications")

---@class Device
---@field id string
---@field name string
---@field os string
---@field platform PlatformId

local M = {}

M.scriptPath = vim.fn.expand("~/Library/xcodebuild.nvim/remote_debugger")

local devices_without_os_version = {}

---Checks whether the `sudo` command has passwordless access to the given {path}.
---@param path string
---@return boolean
local function check_sudo(path)
  local permissions = util.shell("sudo -l")

  for _, line in ipairs(permissions) do
    if line:match("NOPASSWD.*" .. path) then
      return true
    end
  end

  return false
end

---Returns RSD parameter from the output of the `remote_debugger` tool.
---
---The script returns:
---
---UDID: 00003212-00231ASDA1131
---ProductType: iPhone13,3
---ProductVersion: 17.3.1
---Interface: utun6
---Protocol: TunnelProtocol.QUIC
---RSD Address: ab01:e321:2171::1
---RSD Port: 57140
---Use the follow connection option:
--- --rsd ab01:e321:2171::1 57140
---
---@param callback fun(rsd: string)|nil
---@return fun(_, data: string[], _)
local function wait_for_rsd_param(callback)
  local rsdParam

  return function(_, data, _)
    if rsdParam then
      return
    end

    for _, line in ipairs(data) do
      rsdParam = string.match(line, "(%-%-rsd [^%s]+ %d+)")
      if rsdParam then
        util.call(callback, rsdParam)
        return
      end
    end
  end
end

---Checks if the device is disconnected.
---Updates the `M.deviceDisconnected` flag when
---"Device is not connected" message is found in the output.
---@return fun(_, data: string[], _)
local function check_if_device_disconnected()
  M.deviceDisconnected = false

  return function(_, data, _)
    if M.deviceDisconnected then
      return
    end

    for _, line in ipairs(data) do
      if string.find(line, "Device is not connected") then
        M.deviceDisconnected = true
      end
    end
  end
end

---Processes the exit code of the `remote_debugger` tool and
---sends an error notification if the tool failed to start.
---@return fun(_, code: number, _)
local function process_remote_debugger_exit()
  return function(_, code, _)
    if M.deviceDisconnected then
      notifications.send_error("Device is not connected")
    elseif code == 1 then
      notifications.send_error(
        "Failed to start remote debugger. Make sure that you installed the remote_debugger tool. See: `:h xcodebuild.remote-debugger`."
      )
    elseif code ~= 0 and code ~= 143 and code ~= 137 then
      notifications.send_error("Failed to start remote debugger (code: " .. code .. ")")
    end
  end
end

---Waits for the connection string from the `remote_debugger` tool.
---The tool prints:
---
---(lldb) platform select remote-ios
---(lldb) target create /path/to/local/application.app
---(lldb) script lldb.target.module[0].SetPlatformFileSpec(lldb.SBFileSpec('/private/var/containers/Bundle/Application/<APP-UUID>/application.app'))
---(lldb) process connect connect://[127.0.0.1]:65211   <-- ACTUAL CONNECTION DETAILS!
---(lldb) process launch
---
---@param callback fun(connection_string: string)|nil
---@return fun(_, data: string[], _)
local function wait_for_connection_string(callback)
  local connection_string

  return function(_, data, _)
    if connection_string then
      return
    end

    for _, line in ipairs(data) do
      local cmd = string.match(line, "%(lldb%) (process connect .*%d)%s+%<")
      if cmd then
        connection_string = cmd
        util.call(callback, connection_string)
        return
      end
    end
  end
end

---Processes the exit code of the `remote_debugger` tool and
---sends an error notification if the tool failed to start.
---@return fun(_, code: number, _)
local function process_remote_debugger_legacy_exit()
  return function(_, code, _)
    if code == 1 then
      notifications.send_error("Failed to start remote debugger. Make sure that your device is connected")
    elseif code ~= 0 and code ~= 143 and code ~= 137 and code ~= 129 then
      notifications.send_error("Failed to start remote debugger (code: " .. code .. ")")
    end
  end
end

---Returns a function that sends an error notification if the
---code is not 0. Otherwise, it calls the provided callback.
---@param action string
---@param callback function|nil
---@return fun(_, code: number, _)
local function callback_or_error(action, callback)
  return function(_, code, _)
    if code ~= 0 then
      notifications.send_error("Could not " .. action .. " app (code: " .. code .. ")")
    else
      util.call(callback)
    end
  end
end

---Tries to fetch the OS version of the device with the provided id.
---If OS version is already known or the device was already checked,
---it does nothing. Otherwise, it updates project settings.
---@param id string # device id
local function try_fetching_os_version(id)
  local settings = require("xcodebuild.project.config").settings

  if settings.os or devices_without_os_version[id] then
    return
  end

  M.get_connected_devices(function(devices)
    for _, device in ipairs(devices) do
      if device.id == id then
        settings.os = device.os
        require("xcodebuild.project.config").save_settings()
        return
      end
    end

    devices_without_os_version[id] = true
  end)
end

---Checks if the `pymobiledevice` integration is enabled and the tool is installed.
---@return boolean
function M.is_enabled()
  local config = require("xcodebuild.core.config").options.integrations.pymobiledevice

  return config.enabled and M.is_installed()
end

---Checks if the `pymobiledevice3` tool is installed.
---@return boolean
function M.is_installed()
  return vim.fn.executable("pymobiledevice3") ~= 0
end

---Validates if the `pymobiledevice3` tool is installed.
---If not, it sends an error notification.
---@return boolean
function M.validate_installation()
  local config = require("xcodebuild.core.config").options.integrations.pymobiledevice
  if not config.enabled then
    notifications.send_error(
      "pymobiledevice integration is disabled. Please enable it in the configuration to debug on physical devices."
    )
    return false
  end

  if not M.is_installed() then
    notifications.send_error(
      "pymobiledevice3 tool not found. Please run `python3 -m pip install -U pymobiledevice3` to install it."
    )
    return false
  end

  return true
end

---Checks if the `pymobiledevice3` tool is installed and
---if it should be used. The tools is used only for physical devices
---with iOS below 17. If the iOS version is unknown, it tries to fetch it
---and returns false.
---
---This function is intended to check if the tool should be used
---for actions like install, uninstall, and run the application.
---
---This tool should be always used for debugging if it's installed.
---@return boolean
function M.should_use()
  if not M.is_enabled() then
    return false
  end

  local settings = require("xcodebuild.project.config").settings
  if not settings.os then
    try_fetching_os_version(settings.destination)
  end

  local majorVersion = helpers.get_major_os_version()
  if settings.platform == constants.Platform.IOS_DEVICE and majorVersion and majorVersion < 17 then
    return true
  else
    return false
  end
end

---Installs the application on the device.
---@param destination string # device id
---@param appPath string # device path to the app
---@param callback function|nil
---@return number # job id
function M.install_app(destination, appPath, callback)
  local command = {
    "pymobiledevice3",
    "apps",
    "install",
    appPath,
    "--udid",
    destination,
  }

  return vim.fn.jobstart(command, {
    on_exit = callback_or_error("install", callback),
  })
end

---Uninstalls the application with the provided bundle id.
---@param destination string # device id
---@param bundleId string
---@param callback function|nil
---@return number # job id
function M.uninstall_app(destination, bundleId, callback)
  local command = {
    "pymobiledevice3",
    "apps",
    "uninstall",
    bundleId,
    "--udid",
    destination,
  }

  return vim.fn.jobstart(command, {
    on_exit = callback_or_error("uninstall", callback),
  })
end

---Launches the application with the provided bundle id.
---@param destination string # device id
---@param bundleId string
---@param callback function|nil
---@return number # job id
function M.launch_app(destination, bundleId, callback)
  local command = {
    "pymobiledevice3",
    "developer",
    "dvt",
    "launch",
    bundleId,
    "--udid",
    destination,
  }

  local appdata = require("xcodebuild.project.appdata")
  local env = appdata.read_env_vars()
  if env then
    table.insert(command, "--env")

    for key, value in pairs(env) do
      table.insert(command, key)
      table.insert(command, value)
    end
  end

  for _, value in ipairs(appdata.read_run_args() or {}) do
    table.insert(command, value)
  end

  return vim.fn.jobstart(command, {
    on_exit = callback_or_error("launch", callback),
  })
end

---Kills the application with the provided name.
---@param appName string
---@param callback function|nil
---@return number # job id
function M.kill_app(appName, callback)
  local command = {
    "pymobiledevice3",
    "developer",
    "dvt",
    "pkill",
    appName,
  }

  return vim.fn.jobstart(command, {
    on_exit = callback_or_error("kill", callback),
  })
end

---Returns the list of connected devices.
---@param callback fun(devices: Device[])|nil
---@return number # job id
function M.get_connected_devices(callback)
  local cmd = {
    "pymobiledevice3",
    "usbmux",
    "list",
    "--usb",
    "--no-color",
  }

  return vim.fn.jobstart(cmd, {
    stdout_buffered = true,
    on_stdout = function(_, data, _)
      local devices = {}
      local parsedJson = vim.fn.json_decode(data)

      for _, device in ipairs(parsedJson) do
        if
          device.Identifier
          and device.DeviceName
          and device.ProductType
          and (vim.startswith(device.ProductType, "iPhone") or vim.startswith(device.ProductType, "iPad"))
        then
          table.insert(devices, {
            id = device.Identifier,
            name = device.DeviceName,
            os = device.ProductVersion,
            platform = constants.Platform.IOS_DEVICE,
          })
        end
      end

      util.call(callback, devices)
    end,
  })
end

---Returns the path to the application on the device.
---@param destination string # device id
---@param bundleId string
---@return string|nil # app path
function M.find_app_path(destination, bundleId)
  local apps = util.shell({
    "pymobiledevice3",
    "apps",
    "list",
    "--no-color",
    "--udid",
    destination,
  })
  local json = vim.fn.json_decode(apps)
  local app = json[bundleId]

  return app and app.Path or nil
end

---Returns the PID of the application with the provided name.
---@param processName string
---@return string|nil # pid
function M.find_app_pid(processName)
  if vim.fn.executable("jq") == 0 then
    notifications.send_error("`jq` is required to find the app PID. Please install it.")
    return nil
  end

  local command = "pymobiledevice3 processes ps | "
    .. "jq -r 'to_entries[] | select(.value.ProcessName == \""
    .. processName
    .. "\") | .key'"

  return util.shell(command)[1]
end

---Starts the secure server.
---It is used on devices with iOS 17 and above.
---
---Returns the command to connect to the device using `codelldb`.
---@param destination string # device id
---@param rsd string # rsd parameter
---@return string|nil # connection command
function M.start_secure_server(destination, rsd)
  local rsdParams = vim.split(rsd, " ", { plain = true })
  local command = {
    "pymobiledevice3",
    "developer",
    "debugserver",
    "start-server",
  }
  command = util.merge_array(command, rsdParams)
  command = util.merge_array(command, {
    "--no-color",
    "--udid",
    destination,
  })
  local instruction = util.shell(command)

  for _, line in ipairs(instruction) do
    local cmd = string.match(line, "%(lldb%) (process connect .*%d)%s+%<")
    if cmd then
      return cmd
    end
  end

  error("xcodebuild.nvim: Failed to start debugger. Could not find the command to connect to the device.")
  return nil
end

---Starts the server.
---It is used on devices with iOS below 17.
---
---The callback returns {connection_string} that can be used to connect
---to the device using `codelldb`.
---
---This process must be alive during the debugging session.
---Later, it can be closed with `vim.fn.jobstop({job_id})`.
---@param destination string # device id
---@param port number
---@param callback fun(connection_string: string)|nil
---@return number # job id
function M.start_server(destination, port, callback)
  local cmd = {
    "pymobiledevice3",
    "developer",
    "debugserver",
    "start-server",
    port,
    "--udid",
    destination,
    "--no-color",
  }

  return vim.fn.jobstart(cmd, {
    stdout_buffered = false,
    on_stdout = wait_for_connection_string(callback),
    on_exit = process_remote_debugger_legacy_exit(),
  })
end

---Creates a secure tunnel with the device.
---It is used on devices with iOS 17 and above.
---
---Next with the received {rsd} parameter, the server can be started
---with the `start_secure_server` function.
---
---This process must be alive during the debugging session.
---Later, it can be closed with the `close_secure_tunnel` function.
---
---It can't be stopped with `vim.fn.jobstop(job_id)` because it's
---running with `sudo`.
---
---Requires passwordless `sudo` for the `remote_debugger` tool.
---@param destination string # device id
---@param callback fun(rsd: string)|nil
---@return number|nil # job id
function M.create_secure_tunnel(destination, callback)
  if check_sudo(".local/share/nvim/lazy/xcodebuild.nvim/tools/remote_debugger") then
    notifications.send_error(
      "You are using insecure integration with pymobiledevice3. Please migrate your installation (see: `:h xcodebuild.remote-debugger-migration`)"
    )
    return nil
  end

  if not check_sudo(M.scriptPath) then
    notifications.send_error(
      "remote_debugger tool requires passwordless access to the sudo command. (see: `:h xcodebuild.remote-debugger`)"
    )
    return nil
  end

  local cmd = {
    "sudo",
    M.scriptPath,
    "start",
    destination,
  }

  return vim.fn.jobstart(cmd, {
    stdout_buffered = false,
    stderr_buffered = false,
    on_stderr = check_if_device_disconnected(),
    on_stdout = wait_for_rsd_param(callback),
    on_exit = process_remote_debugger_exit(),
  })
end

---Closes the secure tunnel with the device.
---
---Requires passwordless `sudo` for the `remote_debugger` tool.
function M.close_secure_tunnel()
  util.shell({ "sudo", M.scriptPath, "kill" })
end

return M
