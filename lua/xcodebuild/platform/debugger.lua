---@mod xcodebuild.platform.debugger Debugger
---@brief [[
---This module is responsible for providing the interface to get DAP configurations based
---on the debugger integration used (like lldb, codelldb, etc.).
---@brief ]]

---@class DebuggerIntegration
---@field get_macos_configuration fun() : table
---@field get_ios_configuration fun() : table
---@field get_remote_device_configuration fun(request: string) : table
---@field get_adapter_name fun() : string
---@field get_adapter fun() : table

local M = {
  get_macos_configuration = function()
    return {}
  end,
  get_ios_configuration = function()
    return {}
  end,
  get_remote_device_configuration = function(_)
    return {}
  end,
  get_adapter_name = function()
    return ""
  end,
  get_adapter = function()
    return {}
  end,
}

---Sets the implementation for the debugger integration.
---@param impl DebuggerIntegration
function M.set_implementation(impl)
  M.get_macos_configuration = impl.get_macos_configuration
  M.get_ios_configuration = impl.get_ios_configuration
  M.get_remote_device_configuration = impl.get_remote_device_configuration
  M.get_adapter_name = impl.get_adapter_name
  M.get_adapter = impl.get_adapter
end

return M
