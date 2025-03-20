---@mod xcodebuild.tests.provider Test Provider
---@brief [[
---This module contains the functionality to find tests
---based on the provided options.
---
---It is used by the |xcodebuild.tests.runner| module.
---@brief ]]

---@class TestProviderOptions
---@field selectedTests boolean|nil
---@field currentTest boolean|nil
---@field failingTests boolean|nil

---@class TestProviderTest
---@field name string
---@field class string
---@field filepath string|nil

local M = {}

---Finds tests based on the provided {opts}.
---Returns a tuple with the test class found in the buffer
---and a list of tests.
---
---Set `opts.selectedTests` to true to find all selected tests.
---Set `opts.currentTest` to true to find the current test.
---Set `opts.failingTests` to true to find all failing tests
---across the project.
---@param opts TestProviderOptions
---@return string|nil # className
---@return TestProviderTest[] # tests
function M.find_tests(opts)
  local appdata = require("xcodebuild.project.appdata")
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local selectedClass = nil
  local selectedTests = {}

  for _, line in ipairs(lines) do
    selectedClass = string.match(line, "^[^/]*class ([^:%s]+)%s*:?")
    if selectedClass then
      break
    end
  end

  if opts.selectedTests then
    local lineEnd = vim.api.nvim_win_get_cursor(0)[1]
    local lineStart = vim.fn.getpos("v")[2]
    if lineStart > lineEnd then
      lineStart, lineEnd = lineEnd, lineStart
    end
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<esc>", true, false, true), "x", false)

    for i = lineStart, lineEnd do
      local test = string.match(lines[i], "func (test[^%s%(]+)")
      if test then
        table.insert(selectedTests, {
          name = test,
          class = selectedClass,
        })
      end
    end
  elseif opts.currentTest then
    local winnr = vim.api.nvim_get_current_win()
    local currentLine = vim.api.nvim_win_get_cursor(winnr)[1]

    for i = currentLine, 1, -1 do
      local test = string.match(lines[i], "func (test[^%s%(]+)")
      if test then
        table.insert(selectedTests, {
          name = test,
          class = selectedClass,
        })
        break
      end
    end
  elseif opts.failingTests and appdata.report.failedTestsCount > 0 then
    for _, testsPerClass in pairs(appdata.report.tests) do
      for _, test in ipairs(testsPerClass) do
        if not test.success then
          table.insert(selectedTests, {
            name = test.name,
            class = test.class,
            filepath = test.filepath,
          })
        end
      end
    end
  end

  return selectedClass, selectedTests
end

return M
