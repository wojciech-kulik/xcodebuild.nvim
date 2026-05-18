---@toc xcodebuild.contents

---@mod xcodebuild Introduction
---@brief [[
---Xcodebuild.nvim is a plugin designed to let you migrate your app
---app development from Xcode to Neovim. It provides all essential actions
---for development including building, debugging, and testing.
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
---@param options table|nil
local function validate_options(options)
  if not options then
    return
  end

  if
    options.test_explorer
    and options.test_explorer.open_command
    and not string.find(options.test_explorer.open_command, "Test Explorer")
  then
    print(
      'xcodebuild.nvim: Make sure that your `test_explorer.open_command` option creates a buffer with "Test Explorer" name.'
    )
    print("xcodebuild.nvim: Otherwise, restoring Test Explorer on start won't work.")
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
    print("xcodebuild.nvim: Please see `:h xcodebuild.config` and update your config.")
  end

  if
    type(config.commands.extra_test_args) == "string"
    or type(config.commands.extra_build_args) == "string"
  then
    print("xcodebuild.nvim: `commands.extra_test_args` and `commands.extra_build_args` should be a table.")
    print("xcodebuild.nvim: Please see `:h xcodebuild.config` and update your config.")
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
---  project_config = {
---    store_in_project_dir = true, -- if true, the configuration directory is stored in the project directory. If false, it's stored in a global nvim data directory
---    search_in_parent_dirs = false, -- search for configuration in parent directories
---    reload_on_cwd_change = false, -- detect when the current working directory changes and update the configuration accordingly
---  },
---  test_search = {
---    file_matching = "filename_lsp", -- one of: filename, lsp, lsp_filename, filename_lsp. Check out README for details
---    target_matching = true, -- checks if the test file target matches the one from logs. Try disabling it in case of not showing test results
---    lsp_client = "sourcekit", -- name of your LSP for Swift files
---    lsp_timeout = 200, -- LSP timeout in milliseconds
---  },
---  commands = {
---    extra_build_args = { "-parallelizeTargets" }, -- extra arguments for `xcodebuild build`
---    extra_test_args = { "-parallelizeTargets" }, -- extra arguments for `xcodebuild test`
---    project_search_max_depth = 3, -- maxdepth of xcodeproj/xcworkspace search while using configuration wizard
---    focus_simulator_on_app_launch = true, -- focus simulator window when app is launched
---    keep_device_cache = false, -- keep device cache even if scheme or project file changes
---  },
---  logs = { -- build & test logs
---    auto_open_on_success_tests = false, -- open logs when tests succeeded
---    auto_open_on_failed_tests = false, -- open logs when tests failed
---    auto_open_on_success_build = false, -- open logs when build succeeded
---    auto_open_on_failed_build = true, -- open logs when build failed
---    auto_close_on_app_launch = false, -- close logs when app is launched
---    auto_close_on_success_build = false, -- close logs when build succeeded (only if auto_open_on_success_build=false)
---    auto_focus = true, -- focus logs buffer when opened
---    filetype = "", -- file type set for buffer with logs
---    open_command = "silent botright 20split {path}", -- command used to open logs panel. You must use {path} variable to load the log file
---    logs_formatter = "xcbeautify --disable-colored-output --disable-logging", -- command used to format logs, you can use "" to skip formatting
---    only_summary = false, -- if true logs won't be displayed, just xcodebuild.nvim summary
---    live_logs = true, -- if true logs will be updated in real-time
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
---  },
---  quickfix = {
---    show_errors_on_quickfixlist = true, -- add build/test errors to quickfix list
---    show_warnings_on_quickfixlist = true, -- add build warnings to quickfix list
---  },
---  test_explorer = {
---    enabled = true, -- enable Test Explorer
---    auto_open = true, -- open Test Explorer when tests are started
---    auto_focus = true, -- focus Test Explorer when opened
---    open_command = "botright 42vsplit Test Explorer", -- command used to open Test Explorer, must create a buffer with "Test Explorer" name
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
---  project_manager = {
---    guess_target = true, -- guess target for the new file based on the file path
---    find_xcodeproj = false, -- instead of using configured xcodeproj search for xcodeproj closest to targeted file
---    should_update_project = function(path) -- path can lead to directory or file
---      -- it could be useful if you mix Xcode project with SPM for example
---      return true
---    end,
---    project_for_path = function(path)
---      -- you can return a different project for the given {path} (could be directory or file)
---      -- ex.: return "/your/path/to/project.xcodeproj"
---      return nil
---    end,
---  },
---  previews = {
---    open_command = "vertical botright split +vertical\\ resize\\ 42 %s | wincmd p", -- command used to open preview window
---    show_notifications = true, -- show preview-related notifications
---  },
---  device_picker = {
---    mappings = {
---      move_up_device = "<M-y>", -- move device up in the list
---      move_down_device = "<M-e>", -- move device down in the list
---      add_device = "<M-a>", -- add device to cache
---      delete_device = "<M-d>", -- delete device from cache
---      refresh_devices = "<C-r>", -- refresh devices list
---    },
---  },
---  macro_picker = {
---    auto_show_on_error = true, -- automatically show macro approval picker when build fails due to unapproved macros
---    mappings = {
---      approve_macro = "<C-a>", -- approve the selected macro
---    },
---  },
---  integrations = {
---    pymobiledevice = {
---      enabled = true, -- enable pymobiledevice integration (requires configuration, see: `:h xcodebuild.remote-debugger`)
---      remote_debugger_port = 65123, -- port used by remote debugger (passed to pymobiledevice3)
---    },
---    xcodebuild_offline = {
---      enabled = false, -- improves build time when using Xcode below 26 (requires configuration, see `:h xcodebuild.xcodebuild-offline`)
---    },
---    xcode_build_server = {
---      enabled = true, -- enable calling "xcode-build-server config" when project config changes
---      guess_scheme = false, -- run "xcode-build-server config" with the scheme matching the current file's target
---    },
---    nvim_tree = {
---      enabled = true, -- enable updating Xcode project files when using nvim-tree
---    },
---    neo_tree = {
---      enabled = true, -- enable updating Xcode project files when using neo-tree.nvim
---    },
---    oil_nvim = {
---      enabled = true, -- enable updating Xcode project files when using oil.nvim
---    },
---    quick = { -- integration with Swift test framework: github.com/Quick/Quick
---      enabled = true, -- enable Quick tests support (requires Swift parser for nvim-treesitter)
---    },
---    telescope_nvim = {
---      enabled = true, -- enable telescope picker
---    },
---    snacks_nvim = {
---      enabled = true, -- enable Snacks.nvim picker
---      layout = nil,   -- Snacks layout config, check Snacks docs for details
---    },
---    fzf_lua = {
---      enabled = true, -- enable fzf-lua picker
---      fzf_opts = {},  -- fzf options
---      win_opts = {},  -- window options
---    },
---    codelldb = {
---      enabled = false, -- enable codelldb dap adapter for Swift debugging
---      port = 13000, -- port used by codelldb adapter
---      codelldb_path = nil, -- path to codelldb binary, REQUIRED, example: "/Users/xyz/tools/codelldb/extension/adapter/codelldb"
---      lldb_lib_path = "/Applications/Xcode.app/Contents/SharedFrameworks/LLDB.framework/Versions/A/LLDB", -- path to lldb library
---    },
---    lldb = {
---      port = 13000, -- port used by lldb-dap
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
  validate_options(options)
  require("xcodebuild.core.config").setup(options)

  M.setup_modules()
  M.setup_commands()
  setupHighlights()
  warnAboutOldConfig()
end

---Sets up user commands for xcodebuild.nvim
function M.setup_commands()
  local command = require("xcodebuild.command")
  command.register_user_command()
end

---Sets up all modules of xcodebuild.nvim
function M.setup_modules()
  local appdata = require("xcodebuild.project.appdata")
  local autocmd = require("xcodebuild.core.autocmd")
  local projectConfig = require("xcodebuild.project.config")
  local coverage = require("xcodebuild.code_coverage.coverage")
  local coverageReport = require("xcodebuild.code_coverage.report")
  local testExplorer = require("xcodebuild.tests.explorer")
  local diagnostics = require("xcodebuild.tests.diagnostics")
  local nvimTree = require("xcodebuild.integrations.nvim-tree")
  local oilNvim = require("xcodebuild.integrations.oil-nvim")
  local neoTree = require("xcodebuild.integrations.neo-tree")
  local xcodeBuildServer = require("xcodebuild.integrations.xcode-build-server")
  local pickers = require("xcodebuild.ui.pickers")

  appdata.setup()
  autocmd.setup()
  projectConfig.setup()
  diagnostics.setup()
  coverage.setup()
  coverageReport.setup()
  testExplorer.setup()
  nvimTree.setup()
  oilNvim.setup()
  neoTree.setup()
  xcodeBuildServer.setup()
  pickers.setup()
end

---Refreshes the plugin to use the correct `{appdir}` based on the current working directory.
function M.update_cwd()
  local appdata = require("xcodebuild.project.appdata")
  local projectConfig = require("xcodebuild.project.config")
  local events = require("xcodebuild.broadcasting.events")

  appdata.setup()
  projectConfig.setup()
  appdata.load_last_report()

  events.cwd_changed()
end

return M
