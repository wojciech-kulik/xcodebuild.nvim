local util = require("xcodebuild.util")
local notifications = require("xcodebuild.broadcasting.notifications")
local helpers = require("xcodebuild.helpers")
local config = require("xcodebuild.core.config")
local appdata = require("xcodebuild.project.appdata")

local M = {}

local devices_without_os_version = {}

local function get_tool_path()
  return config.options.commands.remote_debugger or appdata.tool_path(REMOTE_DEBUGGER_TOOL)
end

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

local function process_remote_debugger_exit()
  return function(_, code, _)
    if M.deviceDisconnected then
      notifications.send_error("Device is not connected")
    elseif code == 1 then
      notifications.send_error(
        "Failed to start remote debugger. Make sure that you added the remote_debugger tool to sudoers file."
      )
      notifications.send_error(
        "You can do this by running `sudo visudo -f /etc/sudoers` and adding the following line:\n"
          .. vim.fn.expand("$USER")
          .. " ALL = (ALL) NOPASSWD: "
          .. get_tool_path()
      )
    elseif code ~= 0 and code ~= 143 and code ~= 137 then
      notifications.send_error("Failed to start remote debugger (code: " .. code .. ")")
    end
  end
end

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

local function process_remote_debugger_legacy_exit()
  return function(_, code, _)
    if code == 1 then
      notifications.send_error("Failed to start remote debugger. Make sure that your device is connected")
    elseif code ~= 0 and code ~= 143 and code ~= 137 and code ~= 129 then
      notifications.send_error("Failed to start remote debugger (code: " .. code .. ")")
    end
  end
end

local function callback_or_error(action, callback)
  return function(_, code, _)
    if code ~= 0 then
      notifications.send_error("Could not " .. action .. " app (code: " .. code .. ")")
    else
      util.call(callback)
    end
  end
end

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

function M.is_installed()
  return vim.fn.executable("pymobiledevice3") ~= 0
end

function M.validate_installation()
  if not M.is_installed() then
    notifications.send_error(
      "pymobiledevice3 tool not found. Please run `python3 -m pip install -U pymobiledevice3` to install it."
    )
    return false
  end

  return true
end

function M.should_use()
  if not M.is_installed() then
    return false
  end

  local settings = require("xcodebuild.project.config").settings
  if not settings.os then
    try_fetching_os_version(settings.destination)
  end

  local majorVersion = helpers.get_major_os_version()
  local result = settings.platform == "iOS" and (not majorVersion or majorVersion < 17)

  return result
end

function M.install_app(destination, appPath, callback)
  local command = "pymobiledevice3 apps install '" .. appPath .. "' --udid " .. destination

  return vim.fn.jobstart(command, {
    on_exit = callback_or_error("installl", callback),
  })
end

function M.uninstall_app(destination, bundleId, callback)
  local command = "pymobiledevice3 apps uninstall " .. bundleId .. " --udid " .. destination

  return vim.fn.jobstart(command, {
    on_exit = callback_or_error("uninstalll", callback),
  })
end

function M.launch_app(destination, bundleId, callback)
  local command = "pymobiledevice3 developer dvt launch " .. bundleId .. " --udid " .. destination

  return vim.fn.jobstart(command, {
    on_exit = callback_or_error("launch", callback),
  })
end

function M.kill_app(appName, callback)
  local command = "pymobiledevice3 developer dvt pkill '" .. appName .. "'"

  return vim.fn.jobstart(command, {
    on_exit = callback_or_error("kill", callback),
  })
end

function M.get_connected_devices(callback)
  local cmd = "pymobiledevice3 usbmux list --usb --no-color"

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
            platform = "iOS",
          })
        end
      end

      util.call(callback, devices)
    end,
  })
end

function M.find_app_path(destination, bundleId)
  local apps = util.shell("pymobiledevice3 apps list --no-color --udid " .. destination .. " 2>/dev/null")
  local json = vim.fn.json_decode(apps)
  local app = json[bundleId]

  return app and app.Path
end

function M.start_secure_server(destination, rsd)
  local instruction = util.shell(
    "pymobiledevice3 developer debugserver start-server " .. rsd .. " --no-color" .. " --udid " .. destination
  )

  for _, line in ipairs(instruction) do
    local cmd = string.match(line, "%(lldb%) (process connect .*%d)%s+%<")
    if cmd then
      return cmd
    end
  end

  error("xcodebuild.nvim: Failed to start debugger. Could not find the command to connect to the device.")
  return nil
end

function M.start_server(destination, port, callback)
  local cmd = "pymobiledevice3 developer debugserver start-server "
    .. port
    .. " --udid "
    .. destination
    .. " --no-color"

  return vim.fn.jobstart(cmd, {
    stdout_buffered = false,
    on_stdout = wait_for_connection_string(callback),
    on_exit = process_remote_debugger_legacy_exit(),
  })
end

function M.create_secure_tunnel(destination, callback)
  local cmd = "sudo '" .. get_tool_path() .. "' start " .. destination

  return vim.fn.jobstart(cmd, {
    stdout_buffered = false,
    stderr_buffered = false,
    on_stderr = check_if_device_disconnected(),
    on_stdout = wait_for_rsd_param(callback),
    on_exit = process_remote_debugger_exit(),
  })
end

function M.close_secure_tunnel()
  util.shell("sudo '" .. get_tool_path() .. "' kill 2>/dev/null")
end

return M
