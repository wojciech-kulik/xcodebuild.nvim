local M = {}

local defaults = {
  restore_on_start = true, -- logs, diagnostics, and marks will be loaded on VimEnter (may affect performance)
  auto_save = true, -- save all buffers before running build or tests (command: silent wa!)
  logs = {
    auto_open_on_success_tests = true, -- open logs when tests succeeded
    auto_open_on_failed_tests = true, -- open logs when tests failed
    auto_open_on_success_build = true, -- pen logs when build succeeded
    auto_open_on_failed_build = true, -- open logs when build failed
    auto_focus = true, -- focus logs buffer when opened
    open_command = "silent bo split {path} | resize 20", -- command used to open logs panel. You must use {path} variable to load the log file
    logs_formatter = "xcbeautify --disable-colored-output", -- command used to format logs
    only_summary = false, -- if true logs won't be displayed, just xcodebuild.nvim summary
    show_warnings = true, -- show warnings in logs summary
    notify = function(message, severity) -- function to show notifications from this module (like "Build Failed")
      vim.notify(message, severity)
    end,
    notify_progress = function(message) -- function to show live progress (like during tests)
      vim.cmd("echo '" .. message .. "'")
    end,
  },
  marks = {
    show_signs = true, -- show each test result on the side bar
    success_sign = "✔", -- passed test icon
    failure_sign = "✖", -- failed test icon
    success_sign_hl = "DiagnosticSignOk", -- highlight for success_sign
    failure_sign_hl = "DiagnosticSignError", -- highlight for failure_sign
    show_test_duration = true, -- show each test duration next to its declaration
    success_test_duration_hl = "DiagnosticWarn", -- test duration highlight when test passed
    failure_test_duration_hl = "DiagnosticError", -- test duration highlight when test failed
    show_diagnostics = true, -- add test failures to diagnostics
    file_pattern = "*Tests.swift", -- test diagnostics will try to load for files matching this pattern
  },
  quickfix = {
    show_errors_on_quickfixlist = true, -- add errors to quickfix list
    show_warnings_on_quickfixlist = true, -- add build warnings to quickfix list
  },
}

M.options = defaults

function M.setup(options)
  M.options = vim.tbl_deep_extend("force", defaults, options or {})
end

return M
