local util = require("xcodebuild.util")

local M = {}

function M.get_connected_devices(callback)
  if vim.fn.executable("pymobiledevice3") == 0 then
    util.call(callback, {})
    return nil
  end

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

return M
