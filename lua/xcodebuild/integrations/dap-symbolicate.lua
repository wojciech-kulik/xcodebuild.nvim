---@mod xcodebuild.integrations.dap-symbolicate DAP Symbolicate
---@brief [[
---This module provides a DAP integration for symbolication of crash call stacks.
---@brief ]]

local M = {}

local PLUGIN_ID = "xcodebuild-dap-symbolicate-"

local foundException = false
local crashCallStack = {}

---Escapes magic characters from Lua patterns.
---@param s string # the string to escape
local function escape_magic(s)
  return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%1"))
end

---Symbolicates the given address using the debugger.
---@param address string # the address to symbolicate
---@param callback fun(symbolicated: string) # callback with the symbolicated address
local function repl_symbolicate(address, callback)
  local dap = require("dap")

  dap.listeners.after.event_output[PLUGIN_ID .. address] = function(_, body)
    if body.category == "console" then
      local symbolicated = body.output:match("Summary: [^`]*`?(.*)")
      if symbolicated then
        dap.listeners.after.event_output[PLUGIN_ID .. address] = nil
        callback(symbolicated)
      end
    end
  end

  dap.session():request("evaluate", {
    expression = "image lookup -a " .. address,
    context = "repl",
  })
end

---Symbolicates the crash call stack.
---@param callStack string[]
---@param callback fun(symbolicatedCallStack: string[]) # symbolicated call stack
local function symbolicate(callStack, callback)
  local result = {}

  local co = coroutine.create(function(co)
    for index, line in ipairs(callStack) do
      result[index] = line:gsub("\n", "")

      local address, frame = line:match("(0x%x+)%s*(.*)")
      if not address then
        goto continue
      end

      -- symbolicate the address
      repl_symbolicate(address, function(symbolicated)
        if symbolicated then
          result[index] = line:gsub(escape_magic(frame), symbolicated):gsub("\n", "")
        end

        -- if this is the last line, call the callback
        if index == #callStack then
          vim.schedule(function()
            local output = {
              "",
              "==============================================",
              "",
              "Symbolicated crash call stack:",
              "",
            }
            for _, l in ipairs(result) do
              table.insert(output, l)
            end

            callback(output)
          end)
        end

        -- continue to the next line
        coroutine.resume(co, co)
      end)

      -- wait for the symbolication to finish
      coroutine.yield()

      ::continue::
    end
  end)

  coroutine.resume(co, co)
end

---Collects the crash call stack from the console output.
---@param output string[] # the console output
---@param on_symbolicate fun(symbolicatedCallStack: string[]) # callback with the symbolicated call stack
function M.process_logs(output, on_symbolicate)
  for _, line in ipairs(output) do
    if foundException then
      if line == ")" or line:find("%(0x%x+%s.*%)") then
        if line:find("%(0x%x+%s.*%)") then
          for address in line:gmatch("0x%x+") do
            table.insert(crashCallStack, address .. " XYZ")
          end
        end

        foundException = false

        -- defer to allow DAP print the original output
        vim.defer_fn(function()
          symbolicate(crashCallStack, function(symbolicated)
            on_symbolicate(symbolicated)
          end)
          crashCallStack = {}
        end, 100)

        break
      elseif line ~= "(" then
        table.insert(crashCallStack, line)
      end
    else
      foundException = line:find("__exceptionPreprocess") ~= nil
        or line:find(escape_magic("*** First throw call stack:")) ~= nil
    end
  end
end

---Use to notify the module that the debugger has started.
function M.dap_started()
  foundException = false
  crashCallStack = {}
end

return M
