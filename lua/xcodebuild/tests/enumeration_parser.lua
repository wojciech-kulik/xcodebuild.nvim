---@mod xcodebuild.tests.enumeration_parser Test Enumeration Parser
---@brief [[
---This module contains the parser for the:
---`xcodebuild enumerate-tests` command results.
---
---See |xcodebuild.core.xcode.enumerate_tests| for more details.
---@brief ]]

---@class XcodeTest
---@field id string
---@field target string
---@field class string
---@field name string
---@field enabled boolean

local notifications = require("xcodebuild.broadcasting.notifications")

local M = {}

---Parses the test enumeration results from `xcodebuild` command.
---@param filepath string
---@return XcodeTest[]
---@see xcodebuild.core.xcode.enumerate_tests
function M.parse(filepath)
  local util = require("xcodebuild.util")
  local readResult, jsonContent = util.readfile(filepath)
  if not readResult then
    notifications.send_error("Could not read test list")
    return {}
  end

  local parseResult, json = pcall(vim.fn.json_decode, jsonContent)
  if not parseResult then
    notifications.send_error("Could not parse test list")
    return {}
  end

  if not json.values or not json.values[1] or not json.values[1].enabledTests then
    notifications.send_error("Could not find tests")
    return {}
  end

  local tests = {}

  for _, test in ipairs(json.values[1].enabledTests) do
    local target, class, name = string.match(test.identifier, "([^%/]+)%/([^%/]+)%/(.+)")
    if name then
      table.insert(tests, {
        id = test.identifier,
        target = target,
        class = class,
        name = name,
        enabled = true,
      })
    end
  end

  for _, test in ipairs(json.values[1].disabledTests) do
    local target, class, name = string.match(test.identifier, "([^%/]+)%/([^%/]+)%/(.+)")
    if name then
      table.insert(tests, {
        id = test.identifier,
        target = target,
        class = class,
        name = name,
        enabled = false,
      })
    end
  end

  return tests
end

return M
