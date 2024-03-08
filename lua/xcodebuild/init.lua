---@toc xcodebuild.contents

---@mod xcodebuild Introduction
---@brief [[
---Xcodebuild.nvim is a plugin designed to let you migrate your iOS, iPadOS,
---and macOS app development to Neovim. It provides all essential actions
---for development, including building, launching, and testing.
---
---Make sure to check out Tips & Tricks to improve your development in Neovim:
---https://github.com/wojciech-kulik/xcodebuild.nvim/discussions/categories/tips-tricks
---
---Source Code: https://github.com/wojciech-kulik/xcodebuild.nvim
---
---@brief ]]

local M = {}

---Wraps a function to be called by a command
---@param action function
---@param args table|nil
---@return function
local function call(action, args)
  return function()
    action(args)
  end
end

---Overrides highlights
local function setupHighlights()
  local highlights = require("xcodebuild.core.config").options.highlights or {}

  for hl, color in pairs(highlights) do
    if type(color) == "table" then
      vim.api.nvim_set_hl(0, hl, color)
    elseif vim.startswith(color, "#") then
      vim.api.nvim_set_hl(0, hl, { fg = color })
    else
      vim.api.nvim_set_hl(0, hl, { link = color })
    end
  end
end

---Checks if the user is using a deprecated configuration.
local function warnAboutOldConfig()
  local config = require("xcodebuild.core.config").options

  if
    config.code_coverage.covered
    or config.code_coverage.partially_covered
    or config.code_coverage.not_covered
    or config.code_coverage.not_executable
    or config.code_coverage_report.ok_level_hl_group
    or config.code_coverage_report.warning_level_hl_group
    or config.code_coverage_report.error_level_hl_group
    or config.marks.success_sign_hl
    or config.marks.failure_sign_hl
    or config.marks.success_test_duration_hl
    or config.marks.failure_test_duration_hl
  then
    print("xcodebuild.nvim: Code coverage and marks options related to higlights were changed.")
    print("xcodebuild.nvim: Please see README.md and update your config.")
  end
end

-- stylua: ignore start
---@tag xcodebuild.nvim
---@tag xcodebuild.config
---@tag xcodebuild.options
---Setup and initialize xcodebuild.nvim
---@param options table|nil
---
---All options are optional, below you can see the default values:
---@usage lua [[
---require("xcodebuild").setup({
---  restore_on_start = true, -- logs, diagnostics, and marks will be loaded on VimEnter (may affect performance)
---  auto_save = true, -- save all buffers before running build or tests (command: silent wa!)
---  show_build_progress_bar = true, -- shows [ ...    ] progress bar during build, based on the last duration
---  prepare_snapshot_test_previews = true, -- prepares a list with failing snapshot tests
---  test_search = {
---    file_matching = "filename_lsp", -- one of: filename, lsp, lsp_filename, filename_lsp. Check out README for details
---    target_matching = true, -- checks if the test file target matches the one from logs. Try disabling it in case of not showing test results
---    lsp_client = "sourcekit", -- name of your LSP for Swift files
---    lsp_timeout = 200, -- LSP timeout in milliseconds
---  },
---  commands = {
---    cache_devices = true, -- cache recently loaded devices. Restart Neovim to clean cache.
---    extra_build_args = "-parallelizeTargets", -- extra arguments for `xcodebuild build`
---    extra_test_args = "-parallelizeTargets", -- extra arguments for `xcodebuild test`
---    project_search_max_depth = 3, -- maxdepth of xcodeproj/xcworkspace search while using configuration wizard
---    remote_debugger = nil, -- optional path to local copy of remote_debugger (check out README for details)
---    remote_debugger_port = 65123, -- port used by remote debugger (passed to pymobiledevice3)
---  },
---  logs = { -- build & test logs
---    auto_open_on_success_tests = false, -- open logs when tests succeeded
---    auto_open_on_failed_tests = false, -- open logs when tests failed
---    auto_open_on_success_build = false, -- open logs when build succeeded
---    auto_open_on_failed_build = true, -- open logs when build failed
---    auto_close_on_app_launch = false, -- close logs when app is launched
---    auto_close_on_success_build = false, -- close logs when build succeeded (only if auto_open_on_success_build=false)
---    auto_focus = true, -- focus logs buffer when opened
---    filetype = "objc", -- file type set for buffer with logs
---    open_command = "silent botright 20split {path}", -- command used to open logs panel. You must use {path} variable to load the log file
---    logs_formatter = "xcbeautify --disable-colored-output", -- command used to format logs, you can use "" to skip formatting
---    only_summary = false, -- if true logs won't be displayed, just xcodebuild.nvim summary
---    show_warnings = true, -- show warnings in logs summary
---    notify = function(message, severity) -- function to show notifications from this module (like "Build Failed")
---      vim.notify(message, severity)
---    end,
---    notify_progress = function(message) -- function to show live progress (like during tests)
---      vim.cmd("echo '" .. message .. "'")
---    end,
---  },
---  console_logs = {
---    enabled = true, -- enable console logs in dap-ui
---    format_line = function(line) -- format each line of logs
---      return line
---    end,
---    filter_line = function(line) -- filter each line of logs
---      return true
---    end,
---  },
---  marks = {
---    show_signs = true, -- show each test result on the side bar
---    success_sign = "✔", -- passed test icon
---    failure_sign = "✖", -- failed test icon
---    show_test_duration = true, -- show each test duration next to its declaration
---    show_diagnostics = true, -- add test failures to diagnostics
---    file_pattern = "*Tests.swift", -- test diagnostics will be loaded in files matching this pattern (if available)
---  },
---  quickfix = {
---    show_errors_on_quickfixlist = true, -- add build/test errors to quickfix list
---    show_warnings_on_quickfixlist = true, -- add build warnings to quickfix list
---  },
---  test_explorer = {
---    enabled = true, -- enable Test Explorer
---    auto_open = true, -- open Test Explorer when tests are started
---    auto_focus = true, -- focus Test Explorer when opened
---    open_command = "botright 42vsplit Test Explorer", -- command used to open Test Explorer
---    open_expanded = true, -- open Test Explorer with expanded classes
---    success_sign = "✔", -- passed test icon
---    failure_sign = "✖", -- failed test icon
---    progress_sign = "…", -- progress icon (only used when animate_status=false)
---    disabled_sign = "⏸", -- disabled test icon
---    partial_execution_sign = "‐", -- icon for a class or target when only some tests were executed
---    not_executed_sign = " ", -- not executed or partially executed test icon
---    show_disabled_tests = false, -- show disabled tests
---    animate_status = true, -- animate status while running tests
---    cursor_follows_tests = true, -- moves cursor to the last test executed
---  },
---  code_coverage = {
---    enabled = false, -- generate code coverage report and show marks
---    file_pattern = "*.swift", -- coverage will be shown in files matching this pattern
---    -- configuration of line coverage presentation:
---    covered_sign = "",
---    partially_covered_sign = "┃",
---    not_covered_sign = "┃",
---    not_executable_sign = "",
---  },
---  code_coverage_report = {
---    warning_coverage_level = 60,
---    error_coverage_level = 30,
---    open_expanded = false,
---  },
---  integrations = {
---    xcode_build_server = {
---      enabled = true, -- enable calling "xcode-build-server config" when project config changes
---    },
---    nvim_tree = {
---      enabled = true, -- enable updating Xcode project files when using nvim-tree
---      should_update_project = function(path) -- path can lead to directory or file
---        -- it could be useful if you mix Xcode project with SPM for example
---        return true
---      end,
---    },
---  },
---  highlights = {
---    -- you can override here any highlight group used by this plugin
---    -- simple color: XcodebuildCoverageReportOk = "#00ff00",
---    -- link highlights: XcodebuildCoverageReportOk = "DiagnosticOk",
---    -- full customization: XcodebuildCoverageReportOk = { fg = "#00ff00", bold = true },
---  },
---})
---@usage ]]
function M.setup(options)
  require("xcodebuild.core.config").setup(options)

  local autocmd = require("xcodebuild.core.autocmd")
  local actions = require("xcodebuild.actions")
  local projectConfig = require("xcodebuild.project.config")
  local coverage = require("xcodebuild.code_coverage.coverage")
  local coverageReport = require("xcodebuild.code_coverage.report")
  local testExplorer = require("xcodebuild.tests.explorer")
  local diagnostics = require("xcodebuild.tests.diagnostics")
  local nvimTree = require("xcodebuild.integrations.nvim-tree")

  autocmd.setup()
  projectConfig.load_settings()
  diagnostics.setup()
  coverage.setup()
  coverageReport.setup()
  testExplorer.setup()
  nvimTree.setup()
  setupHighlights()
  warnAboutOldConfig()

  -- Build
  vim.api.nvim_create_user_command("XcodebuildBuild", call(actions.build), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildCleanBuild", call(actions.clean_build), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildBuildRun", call(actions.build_and_run), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildBuildForTesting", call(actions.build_for_testing), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildRun", call(actions.run), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildCancel", call(actions.cancel), { nargs = 0 })

  -- Testing
  vim.api.nvim_create_user_command("XcodebuildTest", call(actions.run_tests), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildTestTarget", call(actions.run_target_tests), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildTestClass", call(actions.run_class_tests), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildTestFunc", call(actions.run_func_test), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildTestSelected", call(actions.run_selected_tests), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildTestFailing", call(actions.run_failing_tests), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildFailingSnapshots", call(actions.show_failing_snapshot_tests), { nargs = 0 })

  -- Coverage
  vim.api.nvim_create_user_command("XcodebuildToggleCodeCoverage", call(actions.toggle_code_coverage), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildShowCodeCoverageReport", call(actions.show_code_coverage_report), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildJumpToNextCoverage", call(actions.jump_to_next_coverage), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildJumpToPrevCoverage", call(actions.jump_to_previous_coverage), { nargs = 0 })

  -- Test Explorer
  vim.api.nvim_create_user_command("XcodebuildTestExplorerShow", call(actions.test_explorer_show), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildTestExplorerHide", call(actions.test_explorer_hide), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildTestExplorerToggle", call(actions.test_explorer_toggle), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildTestExplorerRunSelectedTests", call(actions.test_explorer_run_selected_tests), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildTestExplorerRerunTests", call(actions.test_explorer_rerun_tests), { nargs = 0 })

  -- Pickers
  vim.api.nvim_create_user_command("XcodebuildSetup", call(actions.configure_project), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildPicker", call(actions.show_picker), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildSelectProject", call(actions.select_project), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildSelectScheme", call(actions.select_scheme), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildSelectConfig", call(actions.select_config), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildSelectDevice", call(actions.select_device), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildSelectTestPlan", call(actions.select_testplan), { nargs = 0 })

  -- Logs
  vim.api.nvim_create_user_command("XcodebuildToggleLogs", call(actions.toggle_logs), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildOpenLogs", call(actions.open_logs), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildCloseLogs", call(actions.close_logs), { nargs = 0 })

  -- Project Manager
  vim.api.nvim_create_user_command("XcodebuildProjectManager", call(actions.show_project_manager_actions), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildCreateNewFile", call(actions.create_new_file), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildAddCurrentFile", call(actions.add_current_file), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildDeleteCurrentFile", call(actions.delete_current_file), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildRenameCurrentFile", call(actions.rename_current_file), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildCreateNewGroup", call(actions.create_new_group), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildAddCurrentGroup", call(actions.add_current_group), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildRenameCurrentGroup", call(actions.rename_current_group), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildDeleteCurrentGroup", call(actions.delete_current_group), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildUpdateCurrentFileTargets", call(actions.update_current_file_targets), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildShowCurrentFileTargets", call(actions.show_current_file_targets), { nargs = 0 })

  -- Other
  vim.api.nvim_create_user_command("XcodebuildShowConfig", call(actions.show_current_config), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildBootSimulator", call(actions.boot_simulator), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildCleanDerivedData", call(actions.clean_derived_data), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildInstallApp", call(actions.install_app), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildUninstallApp", call(actions.uninstall_app), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildOpenInXcode", call(actions.open_in_xcode), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildQuickfixLine", call(actions.quickfix_line), { nargs = 0 })
  vim.api.nvim_create_user_command("XcodebuildCodeActions", call(actions.show_code_actions), { nargs = 0 })

  -- Backward compatibility
  vim.api.nvim_create_user_command("XcodebuildUninstall", call(actions.uninstall), { nargs = 0 })
end

return M
