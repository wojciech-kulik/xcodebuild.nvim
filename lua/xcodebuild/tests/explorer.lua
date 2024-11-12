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
---Key mappings:
--- - Press `o` to jump to the test implementation
--- - Press `t` to run selected tests
--- - Press `T` to re-run recently selected tests
--- - Press `R` to reload test list
--- - Press `X` to clear test list
--- - Press `[` to jump to the previous failed test
--- - Press `]` to jump to the next failed test
--- - Press `<cr>` to expand or collapse the current node
--- - Press `<tab>` to expand or collapse all classes
--- - Press `g?` to show all key mappings
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
---@field swiftTestingId string|nil
---@field kind TestExplorerNodeKind
---@field status TestExplorerNodeStatus
---@field name string
---@field hidden boolean
---@field filepath string|nil
---@field lineNumber number|nil
---@field classes TestExplorerNode[]|nil
---@field tests TestExplorerNode[]|nil

---@private
---@class IdToTestNode
---@field test TestExplorerNode
---@field row number|nil

local util = require("xcodebuild.util")
local helpers = require("xcodebuild.helpers")
local config = require("xcodebuild.core.config").options.test_explorer
local notifications = require("xcodebuild.broadcasting.notifications")
local events = require("xcodebuild.broadcasting.events")
local appdata = require("xcodebuild.project.appdata")
local constants = require("xcodebuild.core.constants")

local M = {}

---Tree structure with tests report.
---
---It's a list of targets, each target has a list of classes,
---and each class has a list of tests.
---
---@type TestExplorerNode[]
M.report = {}

local STATUS_NOT_EXECUTED = "not_executed"
local STATUS_PARTIAL_EXECUTION = "partial_execution"
local STATUS_RUNNING = "running"
local STATUS_PASSED = "passed"
local STATUS_FAILED = "failed"
local STATUS_DISABLED = "disabled"

local KIND_TARGET = "target"
local KIND_CLASS = "class"
local KIND_TEST = "test"

local ns = vim.api.nvim_create_namespace("xcodebuild-test-explorer")
local spinnerFrames = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local currentFrame = 1
local last_set_cursor_row = nil
local collapsed_ids = {}
local last_run_tests = {}
local is_notests_message_visible = false

---@type table<number, TestExplorerNode>
local line_to_test = {}

---@type IdToTestNode[]
local id_to_test = {}

---@param text string|nil
---@param number number|nil
---@return string|nil
local function take_testid_components(text, number)
  if not text then
    return nil
  end

  local components = vim.split(text, "/", { plain = true })
  local missingComponents = 3 - #components
  number = number - missingComponents

  if number < 1 then
    return nil
  end

  return table.concat(components, "/", 1, number)
end

local function show_notests_message()
  if not M.bufnr then
    return
  end

  helpers.update_readonly_buffer(M.bufnr, function()
    vim.api.nvim_buf_set_lines(M.bufnr, 0, -1, false, {
      "",
      "  No tests found.",
      "",
      "  Tests will automatically appear",
      "  during a test run.",
      "",
      "  Press `R` to fetch tests",
      "  without running them.",
      "",
      "  Press `g?` to see all key mappings.",
    })
  end)

  for i = 4, 10 do
    vim.api.nvim_buf_add_highlight(M.bufnr, ns, "Comment", i - 1, 0, -1)
  end

  is_notests_message_visible = true
end

local function hide_notests_message()
  if not is_notests_message_visible then
    return
  end

  helpers.update_readonly_buffer(M.bufnr, function()
    vim.api.nvim_buf_set_lines(M.bufnr, 0, -1, false, {})
  end)
  vim.api.nvim_buf_clear_namespace(M.bufnr, ns, 0, -1)

  is_notests_message_visible = false
end

---Saves `M.report` to file.
local function save_tests()
  appdata.write_test_explorer_data(M.report)
end

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

    if test.name then
      table.insert(current_class.tests, {
        id = test.id,
        kind = KIND_TEST,
        status = test.enabled and STATUS_NOT_EXECUTED or STATUS_DISABLED,
        name = test.name,
        filepath = filepath,
        hidden = collapsed_ids[test.target] or collapsed_ids[test.target .. "/" .. test.class] or false,
      })
    end

    ::continue::
  end

  M.report = targets
  appdata.write_test_explorer_data(M.report)
end

---Insert test to `M.report`.
---@param test XcodeTest
---@param status TestExplorerNodeStatus
---@param opts {filepath:string|nil,lineNumber:number|nil,swiftTestingId:string|nil}
---@return integer # number of inserted nodes
---@see TestExplorerReport
local function insert_test(test, status, opts)
  local target = id_to_test[test.target]
  local class = id_to_test[test.target .. "/" .. test.class]
  local testTarget = target and target.test
  local testClass = class and class.test
  local insertedNodes = 0

  local testSearch = require("xcodebuild.tests.search")
  local filepath = opts.filepath or testSearch.find_filepath(test.target, test.class)

  if not config.open_expanded then
    collapsed_ids[test.target .. "/" .. test.class] = true
  end

  if not testTarget then
    testTarget = {
      id = test.target,
      swiftTestingId = take_testid_components(opts.swiftTestingId, 1),
      kind = KIND_TARGET,
      status = test.enabled and status or STATUS_DISABLED,
      name = test.target,
      hidden = false,
      classes = {},
    }
    id_to_test[testTarget.id] = { test = testTarget }
    table.insert(M.report, testTarget)
    insertedNodes = insertedNodes + 1
  end

  if not testClass then
    testClass = {
      id = test.target .. "/" .. test.class,
      swiftTestingId = take_testid_components(opts.swiftTestingId, 2),
      kind = KIND_CLASS,
      status = test.enabled and status or STATUS_DISABLED,
      name = test.class,
      filepath = filepath,
      hidden = collapsed_ids[test.target] or false,
      tests = {},
    }
    id_to_test[testClass.id] = { test = testClass }
    table.insert(testTarget.classes, testClass)
    if not testClass.hidden then
      insertedNodes = insertedNodes + 1
    end
  end

  local testToInsert = {
    id = test.id,
    swiftTestingId = opts.swiftTestingId,
    kind = KIND_TEST,
    status = test.enabled and status or STATUS_DISABLED,
    name = test.name,
    filepath = filepath,
    lineNumber = opts.lineNumber,
    hidden = collapsed_ids[test.target] or collapsed_ids[test.target .. "/" .. test.class] or false,
  }
  id_to_test[testToInsert.id] = { test = testToInsert }
  table.insert(testClass.tests, testToInsert)

  if not testToInsert.hidden then
    insertedNodes = insertedNodes + 1
  end

  return insertedNodes
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

---Updates the test line with the provided data.
---@param testData TestExplorerNode
---@param row number
local function update_test_line(testData, row)
  local text, hls = format_line(testData, row)
  vim.api.nvim_buf_set_lines(M.bufnr, row - 1, row, false, { text })

  for _, hl in ipairs(hls) do
    vim.api.nvim_buf_add_highlight(M.bufnr, ns, hl.group, row - 1, hl.col_start, hl.col_end)
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
---
---If {dontUpdateBuffer} is true, only data structures will
---be updated, but the buffer will remain unchanged.
---@param dontUpdateBuffer boolean|nil
local function refresh_explorer(dontUpdateBuffer)
  local lines = {}
  local highlights = {}
  local row = 1

  line_to_test = {}
  id_to_test = {}

  ---@param data TestExplorerNode
  local add_line = function(data)
    id_to_test[data.id] = { test = data }

    if data.hidden then
      return
    end

    local text, hls = format_line(data, row)
    table.insert(lines, text)

    for _, hl in ipairs(hls) do
      table.insert(highlights, hl)
    end

    id_to_test[data.id].row = row
    line_to_test[row] = data
    row = row + 1
  end

  ---

  for _, target in ipairs(M.report) do
    add_line(target)

    for _, class in ipairs(target.classes) do
      add_line(class)

      for _, test in ipairs(class.tests) do
        add_line(test)
      end
    end
  end

  if not M.bufnr or dontUpdateBuffer or util.is_empty(lines) then
    return
  end

  vim.api.nvim_buf_clear_namespace(M.bufnr, ns, 0, -1)

  helpers.update_readonly_buffer(M.bufnr, function()
    vim.api.nvim_buf_set_lines(M.bufnr, 0, -1, false, lines)
  end)

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
end

---Autoscrolls the cursor to the provided row.
---@param row number|nil
local function autoscroll_cursor(row)
  local winnr = M.bufnr and vim.fn.win_findbuf(M.bufnr)[1]

  if winnr and config.cursor_follows_tests and row and last_set_cursor_row ~= row then
    vim.api.nvim_win_set_cursor(winnr, { row, 0 })
    last_set_cursor_row = row
  end
end

---Updates test status.
---@param target TestExplorerNode
---@param class TestExplorerNode
---@param test TestExplorerNode
---@param status TestExplorerNodeStatus
local function update_status(target, class, test, status)
  test.status = test.status == STATUS_DISABLED and STATUS_DISABLED or status
  class.status = get_aggregated_status(class.tests)
  target.status = get_aggregated_status(target.classes)

  if not M.bufnr then
    return
  end

  helpers.update_readonly_buffer(M.bufnr, function()
    local moveCursorToRow = nil
    local toUpdate = {
      id_to_test[test.id],
      id_to_test[class.id],
      id_to_test[target.id],
    }

    for _, data in ipairs(toUpdate) do
      if data and data.row then
        moveCursorToRow = moveCursorToRow or data.row
        update_test_line(data.test, data.row)
      end
    end

    autoscroll_cursor(moveCursorToRow)
  end)
end

---Animates the status of running tests.
---Sets the `M.timer` variable.
local function animate_status()
  M.timer = vim.fn.timer_start(100, function()
    local winnr = M.bufnr and vim.fn.win_findbuf(M.bufnr)[1]
    if not winnr then
      return
    end

    local firstVisibleRow = vim.fn.line("w0", winnr)
    local lastVisibleRow = vim.fn.line("w$", winnr)

    helpers.update_readonly_buffer(M.bufnr, function()
      for row = firstVisibleRow, lastVisibleRow do
        local data = line_to_test[row]

        if data and data.status == STATUS_RUNNING then
          update_test_line(data, row)
        end
      end
    end)

    currentFrame = currentFrame % 10 + 1
  end, { ["repeat"] = -1 })
end

---Sets up the buffer for the test explorer.
---It also sets up the keymaps and the window options.
local function setup_buffer()
  helpers.buf_set_option(M.bufnr, "modifiable", true)

  helpers.win_set_option(0, "fillchars", "eob: ")
  helpers.win_set_option(0, "wrap", false)
  helpers.win_set_option(0, "number", false)
  helpers.win_set_option(0, "relativenumber", false)
  helpers.win_set_option(0, "scl", "no")
  helpers.win_set_option(0, "spell", false)

  helpers.buf_set_option(M.bufnr, "filetype", "TestExplorer")
  helpers.buf_set_option(M.bufnr, "fileencoding", "utf-8")
  helpers.buf_set_option(M.bufnr, "modified", false)
  helpers.buf_set_option(M.bufnr, "readonly", false)
  helpers.buf_set_option(M.bufnr, "modifiable", false)

  vim.api.nvim_buf_set_keymap(M.bufnr, "n", "q", "<cmd>close<cr>", {})
  vim.api.nvim_buf_set_keymap(M.bufnr, "n", "g?", "", { callback = M.show_help, nowait = true })
  vim.api.nvim_buf_set_keymap(M.bufnr, "n", "t", "", { callback = M.run_selected_tests, nowait = true })
  vim.api.nvim_buf_set_keymap(M.bufnr, "v", "t", "", { callback = M.run_selected_tests, nowait = true })
  vim.api.nvim_buf_set_keymap(M.bufnr, "n", "T", "", { callback = M.repeat_last_run, nowait = true })
  vim.api.nvim_buf_set_keymap(M.bufnr, "n", "X", "", { callback = M.clear, nowait = true })
  vim.api.nvim_buf_set_keymap(M.bufnr, "n", "o", "", { callback = M.open_selected_test, nowait = true })
  vim.api.nvim_buf_set_keymap(M.bufnr, "n", "<cr>", "", { callback = M.toggle_current_node, nowait = true })
  vim.api.nvim_buf_set_keymap(M.bufnr, "n", "<tab>", "", { callback = M.toggle_all_classes, nowait = true })
  vim.api.nvim_buf_set_keymap(M.bufnr, "n", "R", "", {
    callback = function()
      helpers.cancel_actions()
      require("xcodebuild.tests.runner").reload_tests()
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

---Loads the saved state of the Test Explorer.
local function load_saved_state()
  M.report = appdata.read_test_explorer_data() or {}

  if util.is_empty(M.report) then
    return
  end

  local callback = function()
    M.load_autocmd = nil
    M.bufnr = util.get_buf_by_name("Test Explorer")

    if M.bufnr then
      setup_buffer()
      refresh_explorer()
    end
  end

  if util.get_buf_by_name("Test Explorer") then
    callback()
  else
    M.load_autocmd = vim.api.nvim_create_autocmd("BufNewFile", {
      group = vim.api.nvim_create_augroup("xcodebuild-test-explorer", { clear = true }),
      pattern = "Test Explorer",
      once = true,
      callback = callback,
    })
  end
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
  local quick = require("xcodebuild.integrations.quick")

  if filepath then
    local searchPhrase = line_to_test[currentRow].name

    if line_to_test[currentRow].kind == KIND_CLASS then
      searchPhrase = "class " .. searchPhrase
    end

    vim.cmd("wincmd p | e " .. filepath)

    if
      quick.is_enabled()
      and line_to_test[currentRow].kind == KIND_TEST
      and quick.contains_quick_tests(0)
    then
      local quickTests = quick.find_quick_tests(0)
      if quickTests and quickTests[searchPhrase] then
        vim.cmd(tostring(quickTests[searchPhrase].row))
        vim.cmd("normal! zz")
        return
      end
    end

    if line_to_test[currentRow].lineNumber then
      vim.cmd(tostring(line_to_test[currentRow].lineNumber))
    else
      vim.fn.search(searchPhrase, "")
    end

    vim.cmd("execute 'normal! zt'")
  end
end

---Changes status to `running` for all test ids from
---{selectedTests}. If {selectedTests} is nil, then
---all enabled tests will be marked as `running`.
---@param selectedTests string[]|nil test ids
function M.start_tests(selectedTests)
  last_set_cursor_row = nil
  last_run_tests = selectedTests or {}

  for _, target in ipairs(M.report) do
    for _, class in ipairs(target.classes) do
      if
        not next(class.tests)
        and (
          util.is_empty(selectedTests)
          or util.contains(selectedTests, target.id)
          or util.contains(selectedTests, class.id)
        )
      then
        target.status = STATUS_RUNNING
        class.status = STATUS_RUNNING
      end

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

  refresh_explorer()

  if config.animate_status then
    animate_status()
  end
end

---Stops the animation and changes the status of `running`
---tests to `not_executed`.
function M.finish_tests()
  if M.timer then
    vim.fn.timer_stop(M.timer)
    M.timer = nil
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
  save_tests()
end

---Updates the status of the test with the provided {testId}.
---It also updates parent nodes.
---@param testId string
---@param status TestExplorerNodeStatus
---@param opts {filepath:string|nil,lineNumber:number|nil,swiftTestingId:string|nil}
function M.update_test_status(testId, status, opts)
  local idComponents = vim.split(testId, "/", { plain = true })
  local targetId = idComponents[1]
  local classId = table.concat({ idComponents[1], idComponents[2] }, "/")
  local testData = id_to_test[testId]

  hide_notests_message()

  if testData then
    local classData = id_to_test[classId]
    update_status(id_to_test[targetId].test, classData.test, testData.test, status)
  else
    local insertedNodes = insert_test({
      id = testId,
      target = idComponents[1],
      class = idComponents[2],
      name = idComponents[3],
      enabled = true,
    }, status, opts)

    local dontReload = idComponents[1] ~= constants.SwiftTestingTarget
    refresh_explorer(dontReload)

    testData = id_to_test[testId]
    local classData = id_to_test[classId]

    if not M.bufnr then
      update_status(id_to_test[targetId].test, classData.test, testData.test, status)
      return
    end

    -- empty buffer has always 1 line
    if vim.api.nvim_buf_line_count(M.bufnr) == 1 then
      insertedNodes = insertedNodes - 1
    end

    if insertedNodes > 0 then
      helpers.update_readonly_buffer(M.bufnr, function()
        for _ = 1, insertedNodes do
          vim.api.nvim_buf_set_lines(M.bufnr, -1, -1, false, { "" })
        end
      end)
    end

    update_status(id_to_test[targetId].test, classData.test, testData.test, status)
  end
end

---Jumps to the next or previous failed test on the list.
---@param next boolean
function M.jump_to_failed_test(next)
  local winnr = vim.fn.win_findbuf(M.bufnr)
  if not winnr or not winnr[1] then
    return
  end

  vim.fn.search("\\[" .. config.failure_sign .. "\\]", next and "W" or "bW")
end

---Repeats the last executed tests or runs all tests.
function M.repeat_last_run()
  if util.is_empty(M.report) then
    notifications.send_error("No tests are loaded. Please run tests first.")
    return
  end

  helpers.cancel_actions()

  if util.is_empty(last_run_tests) then
    require("xcodebuild.tests.runner").run_tests(nil)
  else
    require("xcodebuild.tests.runner").run_tests(last_run_tests)
  end
end

---Runs the selected tests (in visual-mode).
function M.run_selected_tests()
  if util.is_empty(M.report) then
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
        table.insert(selectedTests, test.swiftTestingId or test.id)
        lastKind = test.kind
      end
    end
  end

  if containsDisabledTests then
    notifications.send_warning("Disabled tests won't be executed")
  end

  if #selectedTests > 0 then
    helpers.cancel_actions()
    require("xcodebuild.tests.runner").run_tests(selectedTests)
  else
    notifications.send_error("Tests not found")
  end
end

---Clears the Test Explorer buffer.
---@param showInfoMessage boolean|nil default: true
function M.clear(showInfoMessage)
  M.finish_tests()
  M.report = {}
  generate_report({})

  if not M.bufnr then
    return
  end

  vim.api.nvim_buf_clear_namespace(M.bufnr, ns, 0, -1)

  helpers.update_readonly_buffer(M.bufnr, function()
    vim.api.nvim_buf_set_lines(M.bufnr, 0, -1, false, {})
  end)

  if showInfoMessage == nil or showInfoMessage then
    show_notests_message()
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

  if not M.bufnr or util.is_empty(vim.fn.win_findbuf(M.bufnr)) then
    if M.load_autocmd then
      vim.api.nvim_del_autocmd(M.load_autocmd)
      M.load_autocmd = nil
    end

    vim.cmd(config.open_command)
    M.bufnr = vim.api.nvim_get_current_buf()
    setup_buffer()
    events.toggled_test_explorer(true, M.bufnr, vim.api.nvim_get_current_win())

    if not config.auto_focus then
      vim.cmd("wincmd p")
    end
  end

  refresh_explorer()

  if util.is_empty(M.report) then
    show_notests_message()
  end
end

---Loads tests and generates the report.
---@param tests XcodeTest[]
function M.load_tests(tests)
  M.finish_tests()
  generate_report(tests)
  refresh_explorer()
end

---Shows the help with mappings.
function M.show_help()
  local helper = require("xcodebuild.helpers")
  local buf = vim.api.nvim_create_buf(false, true)

  vim.api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>q<cr>", { noremap = true, silent = true })
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
    "Test Explorer Mappings",
    "",
    "o  jump to the test implementation",
    "t  run selected tests",
    "T  re-run recently selected tests",
    "R  reload test list",
    "X  clear test list",
    "[  jump to the previous failed test",
    "]  jump to the next failed test",
    "g? show all key mappings",
    "q  close the Test Explorer",
    "",
    "<cr>  toggle the current node",
    "<tab> toggle all classes",
    "",
    "Press q to close this help",
  })
  helper.buf_set_option(buf, "modifiable", false)
  helper.buf_set_option(buf, "readonly", true)

  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    once = true,
    callback = function()
      vim.cmd("close")
    end,
  })

  vim.api.nvim_buf_add_highlight(buf, -1, "XcodebuildTestExplorerTarget", 0, 0, -1)
  for i = 2, 10 do
    vim.api.nvim_buf_add_highlight(buf, -1, "XcodebuildTestExplorerTest", i, 0, 2)
  end
  vim.api.nvim_buf_add_highlight(buf, -1, "XcodebuildTestExplorerTest", 12, 0, 4)
  vim.api.nvim_buf_add_highlight(buf, -1, "XcodebuildTestExplorerTest", 13, 0, 5)
  vim.api.nvim_buf_add_highlight(buf, -1, "XcodebuildTestExplorerTest", 15, 6, 7)

  local width = vim.api.nvim_win_get_width(0)
  local opts = {
    style = "minimal",
    relative = "win",
    width = math.max(30, math.min(40, width - 4)),
    height = 16,
    row = 2,
    col = 2,
    border = "rounded",
  }

  vim.api.nvim_open_win(buf, true, opts)
end

---Sets up the Test Explorer. Loads last report if available.
function M.setup()
  -- stylua: ignore start
  vim.api.nvim_set_hl(0, "XcodebuildTestExplorerTest", { link = "Function", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildTestExplorerClass", { link = "Type", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildTestExplorerTarget", { link = "Keyword", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildTestExplorerTestInProgress", { link = "Operator", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildTestExplorerTestPassed", util.get_hl_without_italic("DiagnosticOk"))
  vim.api.nvim_set_hl(0, "XcodebuildTestExplorerTestFailed", util.get_hl_without_italic("DiagnosticError"))
  vim.api.nvim_set_hl(0, "XcodebuildTestExplorerTestPartialExecution", util.get_hl_without_italic("DiagnosticWarn"))
  vim.api.nvim_set_hl(0, "XcodebuildTestExplorerTestDisabled", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildTestExplorerTestNotExecuted", { link = "Normal", default = true })
  -- stylua: ignore end

  load_saved_state()
end

return M
