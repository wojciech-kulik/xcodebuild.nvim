---@mod xcodebuild.code_coverage.report Code Coverage Report
---@tag xcodebuild.code-coverage-report
---@brief [[
---This module is responsible for showing the code coverage report in a floating window.
---It relies on `nui.nvim` plugin to create the floating window.
---
---`nui.nvim` source code: https://github.com/MunifTanjim/nui.nvim
---
---Key bindings:
--- - `enter` or `tab` - expand or collapse the current node
--- - `o` - open source file
---
---@brief ]]

---@private
---@class CoverageReportFile
---@field id string|nil injected test id
---@field name string
---@field path string
---@field executableLines number
---@field coveredLines number
---@field lineCoverage number percentage (0.0-1.0)

---@private
---@class CoverageReportTarget
---@field name string
---@field executableLines number
---@field coveredLines number
---@field lineCoverage number percentage (0.0-1.0)
---@field files CoverageReportFile[]

---@private
---@class CoverageReport
---@field lineCoverage number percentage (0.0-1.0)
---@field coveredLines number percentage (0.0-1.0)
---@field executableLines number
---@field targets CoverageReportTarget[]

local Popup = require("nui.popup")
local Line = require("nui.line")
local Text = require("nui.text")
local Tree = require("nui.tree")
local event = require("nui.utils.autocmd").event

local util = require("xcodebuild.util")
local config = require("xcodebuild.core.config").options.code_coverage_report
local appdata = require("xcodebuild.project.appdata")
local events = require("xcodebuild.broadcasting.events")

local M = {}

---Reads the coverage report file and parses it.
---@return CoverageReport
local function parse_coverage()
  local lines = vim.fn.readfile(appdata.coverage_report_filepath)
  local coverage = vim.fn.json_decode(lines)

  for _, target in ipairs(coverage.targets) do
    table.sort(target.files, function(a, b)
      return a.lineCoverage < b.lineCoverage
    end)
  end

  table.sort(coverage.targets, function(a, b)
    return a.lineCoverage < b.lineCoverage
  end)

  return coverage
end

---Creates a tree of nodes from the coverage report.
---@param coverage CoverageReport
---@return any
local function get_nodes(coverage)
  local nodes = {}

  for _, target in ipairs(coverage.targets) do
    local children = {}
    for _, file in ipairs(target.files) do
      file.id = target.name .. "/" .. file.name
      table.insert(children, Tree.Node(file))
    end
    table.insert(nodes, Tree.Node(target, children))
  end

  return nodes
end

---Gets the highlight group based on the coverage percentage.
---@param coverage number percentage (0-100)
local function get_hl_group(coverage)
  return coverage < config.error_coverage_level and "XcodebuildCoverageReportError"
    or coverage < config.warning_coverage_level and "XcodebuildCoverageReportWarning"
    or "XcodebuildCoverageReportOk"
end

---Expands all nodes in the tree.
---@param tree any
local function expand_all_nodes(tree)
  for _, node in pairs(tree:get_nodes()) do
    node:expand()
  end
end

---Converts a number to a percentage (0-100).
---@param value number (0.0-1.0)
local function to_percent(value)
  return vim.fn.round(tonumber(value) * 100)
end

---Checks if the coverage report file exists.
---@return boolean
function M.is_report_available()
  return util.file_exists(appdata.coverage_report_filepath)
end

---Opens the code coverage report in a floating window.
function M.open()
  local coverage = parse_coverage()

  local popup = Popup({
    enter = true,
    position = "50%",
    relative = "editor",
    size = {
      width = "40%",
      height = "40%",
    },
    border = {
      style = "rounded",
      text = {
        top = "Code Coverage Report (" .. to_percent(coverage.lineCoverage) .. "%)",
      },
    },
    buf_options = {
      readonly = true,
      modifiable = false,
    },
    win_options = {
      winhighlight = "Normal:Normal,FloatBorder:Normal",
      spell = false,
    },
  })

  popup:mount()
  events.toggled_code_coverage_report(true, vim.api.nvim_win_get_buf(popup.winid), popup.winid)

  popup:on({ event.BufLeave }, function()
    vim.schedule(function()
      popup:unmount()
      events.toggled_code_coverage_report(false, nil, nil)
    end)
  end, { once = true })

  local tree = Tree({
    winid = popup.winid,
    nodes = get_nodes(coverage),
    prepare_node = function(node)
      local line = Line()
      local coveragePercent = to_percent(node.lineCoverage)

      if node:has_children() then
        line:append(node:is_expanded() and "  " or "  ", "SpecialChar")

        line:append("[")
        line:append(Text(coveragePercent .. "%", get_hl_group(coveragePercent)))
        line:append("] ")
        line:append(node.name)

        return line
      end

      line:append("    [")
      line:append(Text(coveragePercent .. "%", get_hl_group(coveragePercent)))
      line:append("] ")
      line:append(node.name)

      return line
    end,
  })

  if config.open_expanded then
    expand_all_nodes(tree)
  end

  local map_options = { remap = false, nowait = true }

  -- exit
  popup:map("n", { "q", "<esc>" }, function()
    popup:unmount()
  end, map_options)

  -- toggle
  local toggle = function()
    local node, linenr = tree:get_node()
    if not node:has_children() then
      node, linenr = tree:get_node(node:get_parent_id())
    end

    if not node:is_expanded() then
      if node:expand() then
        vim.api.nvim_win_set_cursor(popup.winid, { linenr, 0 })
        tree:render()
      end
    elseif node:collapse() then
      vim.api.nvim_win_set_cursor(popup.winid, { linenr, 0 })
      tree:render()
    end
  end
  popup:map("n", "<cr>", toggle, map_options)
  popup:map("n", "<tab>", toggle, map_options)

  -- open
  popup:map("n", "o", function()
    local node = tree:get_node()
    if not node.path then
      return
    end

    popup:unmount()
    vim.cmd(string.format("edit %s", node.path))
  end, map_options)

  tree:render()
end

---Sets up the highlight groups for the code coverage report.
function M.setup()
  vim.api.nvim_set_hl(0, "XcodebuildCoverageReportWarning", { link = "DiagnosticWarn", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildCoverageReportError", { link = "DiagnosticError", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildCoverageReportOk", { link = "DiagnosticOk", default = true })
end

return M
