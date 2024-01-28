local util = require("xcodebuild.util")
local config = require("xcodebuild.config").options.test_explorer
local notifications = require("xcodebuild.notifications")
local testSearch = require("xcodebuild.test_search")

local M = {}

local spinnerFrames = {
  "⠋",
  "⠙",
  "⠹",
  "⠸",
  "⠼",
  "⠴",
  "⠦",
  "⠧",
  "⠇",
  "⠏",
}

local STATUS_NOT_EXECUTED = "not_executed"
local STATUS_RUNNING = "running"
local STATUS_PASSED = "passed"
local STATUS_FAILED = "failed"
local STATUS_DISABLED = "disabled"

local KIND_TARGET = "target"
local KIND_CLASS = "class"
local KIND_TEST = "test"

local currentFrame = 1
local last_update = nil
local line_to_test = {}
local last_run_tests = {}
local ns = vim.api.nvim_create_namespace("xcodebuild-test-explorer")

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

    local filepath = testSearch.find_filepath(test.target, test.class)

    if test.target ~= current_target.name then
      current_target = {
        id = test.target,
        kind = KIND_TARGET,
        status = test.enabled and STATUS_NOT_EXECUTED or STATUS_DISABLED,
        name = test.target,
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
    })

    ::continue::
  end

  M.report = targets
end

local function get_hl_for_status(status)
  if status == STATUS_NOT_EXECUTED then
    return "XcodebuildTestExplorerTestNotExecuted"
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

local function get_icon_for_status(status)
  if status == STATUS_NOT_EXECUTED then
    return config.not_executed_sign
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

local function get_text_hl_for_kind(kind, status)
  if status == STATUS_DISABLED then
    return "XcodebuildTestExplorerTestDisabled"
  elseif kind == KIND_TEST then
    return "XcodebuildTestExplorerTest"
  elseif kind == KIND_CLASS then
    return "XcodebuildTestExplorerClass"
  elseif kind == KIND_TARGET then
    return "XcodebuildTestExplorerTarget"
  end
end

local function format_line(line, row)
  local status = line.status
  local kind = line.kind
  local name = line.name
  local icon = get_icon_for_status(status)
  local icon_len = string.len(icon)
  local text_hl = get_text_hl_for_kind(kind, status)

  local get_highlights = function(col_start, text_highlight)
    return {
      {
        row = row,
        col_start = col_start,
        col_end = icon_len + col_start + 2,
        group = get_hl_for_status(status),
      },
      {
        row = row,
        col_start = icon_len + col_start + 2,
        col_end = -1,
        group = text_highlight,
      },
    }
  end

  if kind == KIND_TEST then
    return string.format("    [%s] %s", icon, name), get_highlights(4, text_hl)
  elseif kind == KIND_CLASS then
    return string.format("  [%s] %s", icon, name), get_highlights(2, text_hl)
  elseif kind == KIND_TARGET then
    return string.format("[%s] %s", icon, name), get_highlights(0, text_hl)
  end
end

local function get_aggregated_status(children)
  local passed = false
  local failed = false
  local disabled = false
  local notExecuted = false

  for _, child in ipairs(children) do
    if child.status == STATUS_RUNNING then
      return STATUS_RUNNING
    elseif child.status == STATUS_FAILED then
      failed = true
      passed = false
    elseif child.status == STATUS_PASSED then
      passed = not failed
    elseif child.status == STATUS_NOT_EXECUTED then
      notExecuted = true
    end
  end

  if notExecuted then
    return STATUS_NOT_EXECUTED
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

local function refresh_progress()
  if not M.bufnr then
    return
  end

  local lines = {}
  local highlights = {}
  local row = 1
  local move_cursor_to_row = nil

  local add_line = function(data)
    local text, hls = format_line(data, row)
    table.insert(lines, text)

    for _, hl in ipairs(hls) do
      table.insert(highlights, hl)
    end

    if config.cursor_follows_tests and last_update == data.id then
      move_cursor_to_row = row
      last_update = nil
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

local function animate_status()
  M.timer = vim.fn.timer_start(100, function()
    refresh_progress()
    currentFrame = currentFrame % 10 + 1
  end, { ["repeat"] = -1 })
end

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
  vim.api.nvim_buf_set_keymap(M.bufnr, "n", "r", "", {
    callback = M.run_selected_tests,
    nowait = true,
  })
  vim.api.nvim_buf_set_keymap(M.bufnr, "v", "r", "", {
    callback = M.run_selected_tests,
    nowait = true,
  })
  vim.api.nvim_buf_set_keymap(M.bufnr, "n", "R", "", {
    callback = M.repeat_last_run,
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
  vim.api.nvim_buf_set_keymap(M.bufnr, "n", "o", "", {
    callback = M.open_selected_test,
    nowait = true,
  })
end

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
    refresh_progress()
  end
end

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

  refresh_progress()
end

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
            last_update = t.id
          end

          if not config.animate_status then
            refresh_progress()
          end

          return
        end
      end
    end
  end
end

function M.jump_to_failed_test(next)
  if not M.report then
    return
  end

  local winnr = vim.fn.win_findbuf(M.bufnr)
  if not winnr or not winnr[1] then
    return
  end

  vim.fn.search("    \\[" .. config.failure_sign .. "\\]", next and "W" or "bW")
end

function M.repeat_last_run()
  if not M.report then
    return
  end

  if util.is_empty(last_run_tests) then
    notifications.send_error("No tests to repeat")
    return
  end

  local coordinator = require("xcodebuild.coordinator")
  coordinator.cancel()
  coordinator.run_tests(last_run_tests)
end

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
    local coordinator = require("xcodebuild.coordinator")
    coordinator.cancel()
    coordinator.run_tests(selectedTests)
  else
    notifications.send_error("Tests not found")
  end
end

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

function M.hide()
  if M.bufnr then
    local winnr = vim.fn.win_findbuf(M.bufnr)
    if winnr and winnr[1] then
      vim.api.nvim_win_close(winnr[1], true)
    end
  end
end

function M.show()
  if not M.report then
    vim.defer_fn(function()
      notifications.send("Loading tests...")
    end, 100)

    require("xcodebuild.coordinator").show_test_explorer(function()
      notifications.send("")
    end)

    return
  end

  if not M.bufnr or util.is_empty(vim.fn.win_findbuf(M.bufnr)) then
    vim.cmd(config.open_command)
    M.bufnr = vim.api.nvim_get_current_buf()
    setup_buffer()
  end

  refresh_progress()
end

function M.load_tests(tests)
  M.finish_tests()
  generate_report(tests)
end

function M.setup()
  vim.api.nvim_set_hl(0, "XcodebuildTestExplorerTest", { link = "@function", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildTestExplorerClass", { link = "@type", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildTestExplorerTarget", { link = "@keyword", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildTestExplorerTestInProgress", { link = "@operator", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildTestExplorerTestPassed", { link = "DiagnosticOk", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildTestExplorerTestFailed", { link = "DiagnosticError", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildTestExplorerTestDisabled", { link = "@comment", default = true })
  vim.api.nvim_set_hl(0, "XcodebuildTestExplorerTestNotExecuted", { link = "@text", default = true })
end

return M
