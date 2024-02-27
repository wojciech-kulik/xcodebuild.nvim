---@mod xcodebuild.tests.explorer Test Explorer
---@tag xcodebuild.test-explorer
---@brief [[
---This module contains the Test Explorer functionality.
---
---The Test Explorer is a UI that shows the status of tests
---and allows the user to run, repeat, and open tests.
---
---Tests are presented as a tree structure with targets,
---classes, and tests.
---
---Key bindings:
--- - Press `o` to jump to the test implementation
--- - Press `t` to run selected tests
--- - Press `T` to re-run recently selected tests
--- - Press `R` to reload test list
--- - Press `[` to jump to the previous failed test
--- - Press `]` to jump to the next failed test
--- - Press `<cr>` to expand or collapse the current node
--- - Press `<tab>` to expand or collapse all classes
--- - Press `q` to close the Test Explorer
---
---@brief ]]

---Report node status.
---@alias TestExplorerNodeStatus
---| 'not_executed'
---| 'partial_execution'
---| 'passed'
---| 'running'
---| 'passed'
---| 'failed'
---| 'disabled'

---Report node type.
---@alias TestExplorerNodeKind
---| 'target'
---| 'class'
---| 'test'

---@class TestExplorerNode
---@field id string
---@field kind TestExplorerNodeKind
---@field status TestExplorerNodeStatus
---@field name string
---@field hidden boolean
---@field filepath string|nil
---@field classes TestExplorerNode[]|nil
---@field tests TestExplorerNode[]|nil

local util = require("xcodebuild.util")
local config = require("xcodebuild.core.config").options.test_explorer
local notifications = require("xcodebuild.broadcasting.notifications")
local events = require("xcodebuild.broadcasting.events")

local M = {}

---Tree structure with tests report.
---
---It's a list of targets, each target has a list of classes,
---and each class has a list of tests.
---

---@type TestExplorerNode[]|nil
M.report = nil

local STATUS_NOT_EXECUTED = "not_executed"
local STATUS_PARTIAL_EXECUTION = "partial_execution"
local STATUS_RUNNING = "running"
local STATUS_PASSED = "passed"
local STATUS_FAILED = "failed"
local STATUS_DISABLED = "disabled"

local KIND_TARGET = "target"
local KIND_CLASS = "class"
local KIND_TEST = "test"

local spinnerFrames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local currentFrame = 1
local last_updated_id = nil
local line_to_test = {}
local last_run_tests = {}
local collapsed_ids = {}
local ns = vim.api.nvim_create_namespace("xcodebuild-test-explorer")

---Generates the report for provided tests.
---Sets the `M.report` variable.
---@param tests XcodeTest[]
---@see TestExplorerReport
local function generate_report(tests)
  local targets = {}
  local current_target = {
    name = "",
    classes = {},
  }
  local current_class = {
    name = "",
    tests = {},
  }

  for _, test in ipairs(tests) do
    if not config.show_disabled_tests and not test.enabled then
      goto continue
    end

    local testSearch = require("xcodebuild.tests.search")
    local filepath = testSearch.find_filepath(test.target, test.class)

    if not config.open_expanded and util.is_empty(M.report) then
      collapsed_ids[test.target .. "/" .. test.class] = true
    end

    if test.target ~= current_target.name then
      current_target = {
        id = test.target,
        kind = KIND_TARGET,
        status = test.enabled and STATUS_NOT_EXECUTED or STATUS_DISABLED,
        name = test.target,
        hidden = false,
        classes = {},
      }
      table.insert(targets, current_target)
    end

    if test.class ~= current_class.name then
      current_class = {
        id = test.target .. "/" .. test.class,
        kind = KIND_CLASS,
        status = test.enabled and STATUS_NOT_EXECUTED or STATUS_DISABLED,
        name = test.class,
        filepath = filepath,
        hidden = collapsed_ids[test.target] or false,
        tests = {},
      }
      table.insert(current_target.classes, current_class)
    end

    table.insert(current_class.tests, {
      id = test.id,
      kind = KIND_TEST,
      status = test.enabled and STATUS_NOT_EXECUTED or STATUS_DISABLED,
      name = test.name,
      filepath = filepath,
      hidden = collapsed_ids[test.target] or collapsed_ids[test.target .. "/" .. test.class] or false,
    })

    ::continue::
  end

  M.report = targets
end

---Gets the highlight group for the provided status.
---@param status TestExplorerNodeStatus
---@return string
local function get_hl_for_status(status)
  if status == STATUS_NOT_EXECUTED then
    return "XcodebuildTestExplorerTestNotExecuted"
  elseif status == STATUS_PARTIAL_EXECUTION then
    return "XcodebuildTestExplorerTestPartialExecution"
  elseif status == STATUS_RUNNING then
    return "XcodebuildTestExplorerTestInProgress"
  elseif status == STATUS_PASSED then
    return "XcodebuildTestExplorerTestPassed"
  elseif status == STATUS_FAILED then
    return "XcodebuildTestExplorerTestFailed"
  elseif status == STATUS_DISABLED then
    return "XcodebuildTestExplorerTestDisabled"
  else
    return "@text"
  end
end

---Gets the icon for the provided status.
---@param status TestExplorerNodeStatus
---@return string
local function get_icon_for_status(status)
  if status == STATUS_NOT_EXECUTED then
    return config.not_executed_sign
  elseif status == STATUS_PARTIAL_EXECUTION then
    return config.partial_execution_sign
  elseif status == STATUS_RUNNING then
    return config.animate_status and spinnerFrames[currentFrame] or config.progress_sign
  elseif status == STATUS_PASSED then
    return config.success_sign
  elseif status == STATUS_FAILED then
    return config.failure_sign
  elseif status == STATUS_DISABLED then
    return config.disabled_sign
  else
    return "@text"
  end
end

---Gets the highlight group for the provided kind and status.
---@param kind TestExplorerNodeKind
---@param status TestExplorerNodeStatus
---@return string
local function get_text_hl_for_kind(kind, status)
  if status == STATUS_DISABLED then
    return "XcodebuildTestExplorerTestDisabled"
  elseif kind == KIND_TEST then
    return "XcodebuildTestExplorerTest"
  elseif kind == KIND_CLASS then
    return "XcodebuildTestExplorerClass"
  elseif kind == KIND_TARGET then
    return "XcodebuildTestExplorerTarget"
  else
    return "XcodebuildTestExplorerTest"
  end
end

---Formats the line for the provided report line.
---@param line TestExplorerNode
---@param row number
---@return string
---@return table
local function format_line(line, row)
  local status = line.status
  local kind = line.kind
  local name = line.name

  local icon = get_icon_for_status(status)
  local text_hl = get_text_hl_for_kind(kind, status)
  local status_hl = get_hl_for_status(status)
  local icon_len = string.len(icon)

  local get_highlights = function(col_start)
    return {
      {
        row = row,
        col_start = col_start,
        col_end = icon_len + col_start + 2,
        group = status_hl,
      },
      {
        row = row,
        col_start = icon_len + col_start + 2,
        col_end = -1,
        group = text_hl,
      },
    }
  end

  if kind == KIND_TEST then
    return string.format("    [%s] %s", icon, name), get_highlights(4)
  elseif kind == KIND_CLASS then
    return string.format("  [%s] %s", icon, name), get_highlights(2)
  else
    return string.format("[%s] %s", icon, name), get_highlights(0)
  end
end

---Gets the aggregated status for the provided children.
---@param children TestExplorerNode[]
---@return TestExplorerNodeStatus
local function get_aggregated_status(children)
  local passed = false
  local failed = false
  local disabled = false
  local executed = false
  local notExecuted = false

  for _, child in ipairs(children) do
    if child.status == STATUS_RUNNING then
      return STATUS_RUNNING
    elseif child.status == STATUS_FAILED then
      failed = true
      passed = false
      executed = true
    elseif child.status == STATUS_PASSED then
      passed = not failed
      executed = true
    elseif child.status == STATUS_NOT_EXECUTED then
      notExecuted = true
    elseif child.status == STATUS_PARTIAL_EXECUTION then
      notExecuted = true
      executed = true
    elseif child.status == STATUS_DISABLED then
      disabled = true
    end
  end

  if notExecuted then
    return executed and STATUS_PARTIAL_EXECUTION or STATUS_NOT_EXECUTED
  elseif failed then
    return STATUS_FAILED
  elseif passed then
    return STATUS_PASSED
  elseif disabled then
    return STATUS_DISABLED
  else
    return STATUS_NOT_EXECUTED
  end
end

---Refreshes the test explorer buffer.
---It also moves the cursor to the last updated test
---if `config.cursor_follows_tests` is enabled.
local function refresh_explorer()
  if not M.bufnr then
    return
  end

  local lines = {}
  local highlights = {}
  local row = 1
  local move_cursor_to_row = nil

  line_to_test = {}

  local add_line = function(data)
    if data.hidden then
      return
    end

    local text, hls = format_line(data, row)
    table.insert(lines, text)

    for _, hl in ipairs(hls) do
      table.insert(highlights, hl)
    end

    if config.cursor_follows_tests and last_updated_id == data.id then
      move_cursor_to_row = row
      last_updated_id = nil
    end

    line_to_test[row] = data
    row = row + 1
  end

  for _, target in ipairs(M.report) do
    add_line(target)

    for _, class in ipairs(target.classes) do
      add_line(class)

      for _, test in ipairs(class.tests) do
        add_line(test)
      end
    end
  end

  vim.api.nvim_buf_clear_namespace(M.bufnr, ns, 0, -1)
  vim.api.nvim_buf_set_option(M.bufnr, "modifiable", true)
  vim.api.nvim_buf_set_lines(M.bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(M.bufnr, "modifiable", false)
  vim.api.nvim_buf_set_option(M.bufnr, "modified", false)

  for _, highlight in ipairs(highlights) do
    vim.api.nvim_buf_add_highlight(
      M.bufnr,
      ns,
      highlight.group,
      highlight.row - 1,
      highlight.col_start,
      highlight.col_end
    )
  end

  if move_cursor_to_row then
    local winnr = vim.fn.win_findbuf(M.bufnr)
    if winnr and winnr[1] then
      vim.api.nvim_win_set_cursor(winnr[1], { move_cursor_to_row, 0 })
    end
  end
end

---Animates the test status.
---Sets the `M.timer` variable.
local function animate_status()
  M.timer = vim.fn.timer_start(100, function()
    refresh_explorer()
    currentFrame = currentFrame % 10 + 1
  end, { ["repeat"] = -1 })
end

---Sets up the buffer for the test explorer.
---It also sets up the keymaps and the window options.
local function setup_buffer()
  vim.api.nvim_buf_set_option(M.bufnr, "modifiable", true)

  vim.api.nvim_win_set_option(0, "fillchars", "eob: ")
  vim.api.nvim_win_set_option(0, "wrap", false)
  vim.api.nvim_win_set_option(0, "number", false)
  vim.api.nvim_win_set_option(0, "relativenumber", false)
  vim.api.nvim_win_set_option(0, "scl", "no")
  vim.api.nvim_win_set_option(0, "spell", false)

  vim.api.nvim_buf_set_option(M.bufnr, "fileencoding", "utf-8")
  vim.api.nvim_buf_set_option(M.bufnr, "modified", false)
  vim.api.nvim_buf_set_option(M.bufnr, "readonly", false)
  vim.api.nvim_buf_set_option(M.bufnr, "modifiable", false)

  vim.api.nvim_buf_set_keymap(M.bufnr, "n", "q", "<cmd>close<cr>", {})
  vim.api.nvim_buf_set_keymap(M.bufnr, "n", "t", "", { callback = M.run_selected_tests, nowait = true })
  vim.api.nvim_buf_set_keymap(M.bufnr, "v", "t", "", { callback = M.run_selected_tests, nowait = true })
  vim.api.nvim_buf_set_keymap(M.bufnr, "n", "T", "", { callback = M.repeat_last_run, nowait = true })
  vim.api.nvim_buf_set_keymap(M.bufnr, "n", "o", "", { callback = M.open_selected_test, nowait = true })
  vim.api.nvim_buf_set_keymap(M.bufnr, "n", "<cr>", "", { callback = M.toggle_current_node, nowait = true })
  vim.api.nvim_buf_set_keymap(M.bufnr, "n", "<tab>", "", { callback = M.toggle_all_classes, nowait = true })
  vim.api.nvim_buf_set_keymap(M.bufnr, "n", "R", "", {
    callback = function()
      require("xcodebuild.tests.runner").show_test_explorer(function()
        notifications.send("")
      end)
    end,
    nowait = true,
  })
  vim.api.nvim_buf_set_keymap(M.bufnr, "n", "[", "", {
    callback = function()
      M.jump_to_failed_test(false)
    end,
    nowait = true,
  })
  vim.api.nvim_buf_set_keymap(M.bufnr, "n", "]", "", {
    callback = function()
      M.jump_to_failed_test(true)
    end,
    nowait = true,
  })
end

---Collapses or expands all classes.
function M.toggle_all_classes()
  local newState = nil

  for _, line in ipairs(line_to_test) do
    if line.kind == KIND_CLASS then
      if newState == nil then
        newState = collapsed_ids[line.id] == nil or not collapsed_ids[line.id]
      end

      collapsed_ids[line.id] = newState

      for _, test in ipairs(line.tests) do
        test.hidden = newState
      end
    end
  end

  refresh_explorer()
end

---Collapses or expands the current node.
function M.toggle_current_node()
  local currentRow = vim.api.nvim_win_get_cursor(0)[1]
  local line = line_to_test[currentRow]

  if not line then
    return
  end

  local newState = collapsed_ids[line.id] == nil or not collapsed_ids[line.id]

  if line.kind == KIND_TEST then
    for i = currentRow - 1, 1, -1 do
      line = line_to_test[i]

      if line.kind == KIND_CLASS then
        collapsed_ids[line.id] = true

        for _, test in ipairs(line.tests) do
          test.hidden = true
        end

        vim.api.nvim_win_set_cursor(0, { i, 0 })
        break
      end
    end
  elseif line.kind == KIND_CLASS then
    collapsed_ids[line.id] = newState

    for _, test in ipairs(line.tests) do
      test.hidden = newState
    end
  elseif line.kind == KIND_TARGET then
    collapsed_ids[line.id] = newState

    for _, class in ipairs(line.classes) do
      class.hidden = newState
      collapsed_ids[class.id] = newState

      for _, test in ipairs(class.tests) do
        test.hidden = newState
      end
    end
  end

  refresh_explorer()
end

---Opens the selected test or class under the cursor.
---It navigates to the previous window to avoid
---navigation in Test Explorer window.
function M.open_selected_test()
  local currentRow = vim.api.nvim_win_get_cursor(0)[1]
  if not line_to_test[currentRow] then
    return
  end

  local filepath = line_to_test[currentRow].filepath

  if filepath then
    local searchPhrase = line_to_test[currentRow].name

    if line_to_test[currentRow].kind == KIND_CLASS then
      searchPhrase = "class " .. searchPhrase
    end

    vim.cmd("wincmd p | e " .. filepath)
    vim.fn.search(searchPhrase, "")
    vim.cmd("execute 'normal! zt'")
  end
end

---Changes status to `running` for all test ids from
---{selectedTests}. If {selectedTests} is nil, then
---all enabled tests will be marked as `running`.
---@param selectedTests string[]|nil test ids
function M.start_tests(selectedTests)
  if not M.report then
    return
  end

  last_run_tests = selectedTests

  for _, target in ipairs(M.report) do
    for _, class in ipairs(target.classes) do
      for _, test in ipairs(class.tests) do
        if
          util.is_empty(selectedTests)
          or util.contains(selectedTests, target.id)
          or util.contains(selectedTests, class.id)
          or util.contains(selectedTests, test.id)
        then
          if test.status ~= STATUS_DISABLED then
            target.status = STATUS_RUNNING
            class.status = STATUS_RUNNING
            test.status = STATUS_RUNNING
          end
        end
      end
    end
  end

  if config.animate_status then
    animate_status()
  else
    refresh_explorer()
  end
end

---Stops the animation and changes the status of `running`
---tests to `not_executed`.
function M.finish_tests()
  if M.timer then
    vim.fn.timer_stop(M.timer)
    M.timer = nil
  end

  if not M.report then
    return
  end

  for _, target in ipairs(M.report) do
    for _, class in ipairs(target.classes) do
      for _, test in ipairs(class.tests) do
        if test.status == STATUS_RUNNING then
          test.status = STATUS_NOT_EXECUTED
        end
      end

      if class.status == STATUS_RUNNING then
        class.status = get_aggregated_status(class.tests)
      end
    end

    if target.status == STATUS_RUNNING then
      target.status = get_aggregated_status(target.classes)
    end
  end

  refresh_explorer()
end

---Updates the status of the test with the provided {testId}.
---It also updates parent nodes.
---@param testId string
---@param status TestExplorerNodeStatus
function M.update_test_status(testId, status)
  if not M.report then
    return
  end

  for _, target in ipairs(M.report) do
    for _, class in ipairs(target.classes) do
      for _, t in ipairs(class.tests) do
        if t.id == testId then
          t.status = t.status == STATUS_DISABLED and STATUS_DISABLED or status
          class.status = get_aggregated_status(class.tests)
          target.status = get_aggregated_status(target.classes)

          if status == STATUS_PASSED or status == STATUS_FAILED then
            if t.hidden then
              last_updated_id = class.hidden and target.id or class.id
            else
              last_updated_id = t.id
            end
          end

          if not config.animate_status then
            refresh_explorer()
          end

          return
        end
      end
    end
  end
end

---Jumps to the next or previous failed test on the list.
---@param next boolean
function M.jump_to_failed_test(next)
  if not M.report then
    return
  end

  local winnr = vim.fn.win_findbuf(M.bufnr)
  if not winnr or not winnr[1] then
    return
  end

  vim.fn.search("\\[" .. config.failure_sign .. "\\]", next and "W" or "bW")
end

---Repeats the last executed tests.
function M.repeat_last_run()
  if not M.report then
    return
  end

  if util.is_empty(last_run_tests) then
    notifications.send_error("No tests to repeat")
    return
  end

  require("xcodebuild.helpers").cancel_actions()
  require("xcodebuild.tests.runner").run_tests(last_run_tests, { skipEnumeration = true })
end

---Runs the selected tests (in visual-mode).
function M.run_selected_tests()
  if not M.report then
    return
  end

  local containsDisabledTests = false
  local selectedTests = {}
  local lastKind = nil
  local lineEnd = vim.api.nvim_win_get_cursor(0)[1]
  local lineStart = vim.fn.getpos("v")[2]
  if lineStart > lineEnd then
    lineStart, lineEnd = lineEnd, lineStart
  end

  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<esc>", true, false, true), "x", false)

  for i = lineStart, lineEnd do
    local test = line_to_test[i]

    if test then
      -- luacheck: ignore

      if test.status == STATUS_DISABLED then
        containsDisabledTests = true
      elseif test.kind == KIND_TEST and lastKind == KIND_CLASS then
        -- skip tests if class is already added
      elseif (test.kind == KIND_TEST or test.kind == KIND_CLASS) and lastKind == KIND_TARGET then
        -- skip tests and classes if target is already added
      else
        table.insert(selectedTests, test.id)
        lastKind = test.kind
      end
    end
  end

  if containsDisabledTests then
    notifications.send_warning("Disabled tests won't be executed")
  end

  if #selectedTests > 0 then
    require("xcodebuild.helpers").cancel_actions()
    require("xcodebuild.tests.runner").run_tests(selectedTests, { skipEnumeration = true })
  else
    notifications.send_error("Tests not found")
  end
end

---Toggles the Test Explorer window.
function M.toggle()
  if not M.bufnr then
    M.show()
    return
  end

  local winnr = vim.fn.win_findbuf(M.bufnr)
  if winnr and winnr[1] then
    M.hide()
  else
    M.show()
  end
end

---Hides the Test Explorer window.
function M.hide()
  if M.bufnr then
    local winnr = vim.fn.win_findbuf(M.bufnr)
    if winnr and winnr[1] then
      vim.api.nvim_win_close(winnr[1], true)
      events.toggled_test_explorer(false, nil, nil)
    end
  end
end

---Shows the Test Explorer window.
function M.show()
  if not config.enabled then
    return
  end

  if not M.report then
    require("xcodebuild.tests.runner").show_test_explorer(function()
      notifications.send("")
    end)

    return
  end

  if not M.bufnr or util.is_empty(vim.fn.win_findbuf(M.bufnr)) then
    vim.cmd(config.open_command)
    M.bufnr = vim.api.nvim_get_current_buf()
    setup_buffer()
    events.toggled_test_explorer(true, M.bufnr, vim.api.nvim_get_current_win())

    if not config.auto_focus then
      vim.cmd("wincmd p")
    end
  end

  refresh_explorer()
end

---Loads tests and generates the report.
---@param tests XcodeTest[]
function M.load_tests(tests)
  if not config.enabled then
    return
  end

  M.finish_tests()
  generate_report(tests)
end

---Sets up the Test Explorer.
function M.setup()
  -- stylua: ignore start
  vim.api.nvim_set_hl(0, "XcodebuildTestExplorerTest", { link = "Function", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildTestExplorerClass", { link = "Type", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildTestExplorerTarget", { link = "Keyword", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildTestExplorerTestInProgress", { link = "Operator", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildTestExplorerTestPassed", { link = "DiagnosticOk", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildTestExplorerTestFailed", { link = "DiagnosticError", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildTestExplorerTestPartialExecution", { link = "DiagnosticWarn", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildTestExplorerTestDisabled", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildTestExplorerTestNotExecuted", { link = "Normal", default = true })
  -- stylua: ignore end
end

return M
