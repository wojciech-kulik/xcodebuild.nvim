local Popup = require("nui.popup")
local Line = require("nui.line")
local Text = require("nui.text")
local Tree = require("nui.tree")
local event = require("nui.utils.autocmd").event

local config = require("xcodebuild.config").options.code_coverage_report
local appdata = require("xcodebuild.appdata")
local util = require("xcodebuild.util")

local M = {}

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

local function get_hl_group(coverage)
  return coverage < config.error_coverage_level and config.error_level_hl_group
    or coverage < config.warning_coverage_level and config.warning_level_hl_group
    or config.ok_level_hl_group
end

local function expand_all_nodes(tree)
  for _, node in pairs(tree:get_nodes()) do
    node:expand()
  end
end

local function to_percent(value)
  return vim.fn.round(tonumber(value) * 100)
end

function M.is_report_available()
  return util.file_exists(appdata.coverage_report_filepath)
end

function M.open()
  local coverage = parse_coverage()

  local popup = Popup({
    enter = true,
    position = "50%",
    size = {
      width = "60%",
      height = "60%",
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
    },
  })

  popup:mount()

  popup:on({ event.BufLeave }, function()
    vim.schedule(function()
      popup:unmount()
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

return M
