# 🛠️ xcodebuild.nvim

A plugin that lets you move your iOS, iPadOS and macOS apps development to Neovim. It supports most of Xcode actions that are required to work with a project, including device selection, building, launching, and testing.

![Xcodebuild Debugging](./media/tests.png)

![Xcodebuild Testing](./media/debug.png)

## 🚧 Disclaimer

This plugin is in the early stage of development. It was tested on a limited number of projects and configurations. Therefore, it still could be buggy. If you find any issue don't hesitate to fix it and create a pull request or just report it.

I've been looking for a solution to move my development to any other IDE than Xcode for a long time. It seems that this plugin + [nvim-dap](https://github.com/mfussenegger/nvim-dap) + [nvim-dap-ui](https://github.com/rcarriga/nvim-dap-ui) + [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) + [xcode-build-server](https://github.com/SolaWing/xcode-build-server), all together, provide everything that is needed to move to Neovim with iOS, iPadOS, and macOS apps development.

Of course, you will still need Xcode for some project setup & management. Also, you may need to migrate to [tuist](https://github.com/tuist/tuist) or [xcodegen](https://github.com/yonaskolb/XcodeGen) to be able to add new files easily.

It is also my first Neovim plugin. Hopefully, a good one 😁.

## ✨ Features

- [x] Support for iOS, iPadOS, and macOS apps.
- [x] Project-based configuration.
- [x] Configuration wizard to setup: project file, scheme, config, device, and test plan.
- [x] Built based on core command line tools like `xcodebuild` and `xcrun simctl`. It doesn't require any external tools, only `xcbeautify` to format logs, but it could be changed in configuration.
- [x] Build, run and test actions.
- [x] App deployment to selected iOS simulator.
- [x] Uninstall mobile app.
- [x] Running only selected tests (one test, one class, selected tests in visual mode, whole test plan).
- [x] Showing icons with test result next to each test.
- [x] Showing test duration next to each test.
- [x] Showing test errors in diagnostics and on the quickfix list.
- [x] Showing build errors and warnings on the quickfix list.
- [x] Showing build progress bar based on the previous build time.
- [x] Showing code coverage.
- [x] Showing preview of failed snapshot tests (if you use [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing))
- [x] Advanced log parser to detect all errors, warnings, and failing tests and to present them nicely formatted.
- [x] Auto saving files before build or test actions.
- [x] [nvim-dap](https://github.com/mfussenegger/nvim-dap) helper functions to let you easily build, run, and attach the debugger.
- [x] [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) integration to show current device and project settings.
- [x] [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) integration to show pickers with selectable project options.
- [x] Picker with all available actions.

## ⚡️ Requirements

- [Neovim](https://neovim.io) (not sure which version, use the latest one 😅).
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) used to present pickers by the plugin.
- [nui.nvim](https://github.com/MunifTanjim/nui.nvim) used to present code coverage report.
- [xcbeautify](https://github.com/tuist/xcbeautify) - Xcode logs formatter (optional - you can set a different tool or disable formatting in the config).
- Xcode (make sure that `xcodebuild` and `xcrun simctl` work correctly).
- To get the best experience with apps development, you should install and configure [nvim-dap](https://github.com/mfussenegger/nvim-dap) and [nvim-dap-ui](https://github.com/rcarriga/nvim-dap-ui) to be able to debug.
- This plugin requires the project to be written in Swift. It was tested only with Xcode 15.
- Make sure to configure LSP properly for iOS/macOS apps. You can read how to do that in my post: [The Complete Guide To iOS & macOS Development In Neovim](https://wojciechkulik.pl/ios/the-complete-guide-to-ios-macos-development-in-neovim).

Install tools:

```shell
brew install xcbeautify
```

## 📦 Installation

Install the plugin using your preferred package manager:

### 💤 [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
return {
  "wojciech-kulik/xcodebuild.nvim",
  dependencies = {
    "nvim-telescope/telescope.nvim",
    "MunifTanjim/nui.nvim",
  },
  config = function()
    require("xcodebuild").setup({
        -- put some options here or leave it empty to use default settings
    })
  end,
}
```

## ⚙️ Configuration

Xcodebuild.nvim comes with the following defaults:

```lua
{
  restore_on_start = true, -- logs, diagnostics, and marks will be loaded on VimEnter (may affect performance)
  auto_save = true, -- save all buffers before running build or tests (command: silent wa!)
  show_build_progress_bar = true, -- shows [ ...    ] progress bar during build, based on the last duration
  prepare_snapshot_test_previews = true, -- prepares a list with failing snapshot tests
  test_search = {
    file_matching = "filename_lsp", -- one of: filename, lsp, lsp_filename, filename_lsp. Check out README for details
    target_matching = true, -- checks if the test file target matches the one from logs. Try disabling it in case of not showing test results
    lsp_client = "sourcekit", -- name of your LSP for Swift files
    lsp_timeout = 200, -- LSP timeout in milliseconds
  },
  commands = {
    cache_devices = true, -- cache recently loaded devices. Restart Neovim to clean cache.
    extra_build_args = "-parallelizeTargets", -- extra arguments for `xcodebuild build`
    extra_test_args = "-parallelizeTargets", -- extra arguments for `xcodebuild test`
    project_search_max_depth = 3, -- maxdepth of xcodeproj/xcworkspace search while using configuration wizard
  },
  logs = {
    auto_open_on_success_tests = false, -- open logs when tests succeeded
    auto_open_on_failed_tests = false, -- open logs when tests failed
    auto_open_on_success_build = false, -- open logs when build succeeded
    auto_open_on_failed_build = true, -- open logs when build failed
    auto_close_on_app_launch = false, -- close logs when app is launched
    auto_close_on_success_build = false, -- close logs when build succeeded (only if auto_open_on_success_build=false)
    auto_focus = true, -- focus logs buffer when opened
    filetype = "objc", -- file type set for buffer with logs
    open_command = "silent bo split {path} | resize 20", -- command used to open logs panel. You must use {path} variable to load the log file
    logs_formatter = "xcbeautify --disable-colored-output", -- command used to format logs, you can use "" to skip formatting
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
    file_pattern = "*Tests.swift", -- test diagnostics will be loaded in files matching this pattern (if available)
  },
  quickfix = {
    show_errors_on_quickfixlist = true, -- add build/test errors to quickfix list
    show_warnings_on_quickfixlist = true, -- add build warnings to quickfix list
  },
  test_explorer = {
    enabled = true, -- enable Test Explorer
    auto_open = true, -- opens Test Explorer when tests are started
    open_command = "bo vertical split Test Explorer", -- command used to open Test Explorer
    success_sign = "✔", -- passed test icon
    failure_sign = "✖", -- failed test icon
    progress_sign = "…", -- progress icon (only used when animate_status=false)
    disabled_sign = "⏸", -- disabled test icon
    not_executed_sign = " ", -- not executed or partially executed test icon
    show_disabled_tests = false, -- show disabled tests
    animate_status = true, -- animate status while running tests
    cursor_follows_tests = true, -- moves cursor to the last test executed
  },
  code_coverage = {
    enabled = false, -- generate code coverage report and show marks
    file_pattern = "*.swift", -- coverage will be shown in files matching this pattern
    -- configuration of line coverage presentation:
    covered = {
      sign_text = "",
      sign_hl_group = "XcodebuildCoverageFull",
      number_hl_group = nil,
      line_hl_group = nil,
    },
    partially_covered = {
      sign_text = "┃",
      sign_hl_group = "XcodebuildCoveragePartial",
      number_hl_group = nil,
      line_hl_group = nil,
    },
    not_covered = {
      sign_text = "┃",
      sign_hl_group = "XcodebuildCoverageNone",
      number_hl_group = nil,
      line_hl_group = nil,
    },
    not_executable = {
      sign_text = "",
      sign_hl_group = "XcodebuildCoverageNotExecutable",
      number_hl_group = nil,
      line_hl_group = nil,
    },
  },
  code_coverage_report = {
    warning_coverage_level = 60,
    warning_level_hl_group = "DiagnosticWarn",
    error_coverage_level = 30,
    error_level_hl_group = "DiagnosticError",
    ok_level_hl_group = "DiagnosticOk",
    open_expanded = false,
  },
}
```

### 🔎 Test File Search - File Matching

`xcodebuild` logs provide the following information about the test: target, test class, and test name. The plugin needs to find the file location based on that, which is not a trivial task.

In order to support multiple cases, the plugin allows you to choose the search mode. It offers four modes to find a test class. You can change it by setting `test_search.file_matching`.

- `filename` - it assumes that the test class name matches the file name. It finds matching files and then based on the build output, it checks whether the file belongs to the desired target.
- `lsp` - it uses LSP to find the class symbol. Each match is checked if it belongs to the desired target.
- `filename_lsp` first try `filename` mode, if it fails try `lsp` mode.
- `lsp_filename` first try `lsp` mode, if it fails try `filename` mode.

`filename_lsp` is the recommended mode, because `filename` search is faster than `lsp`, but you also have `lsp` fallback if there is no match from `filename`.

👉 If you notice that your test results don't appear or appear in incorrect files, try playing with these modes.

👉 If your test results don't appear, you can also try disabling `test_search.target_matching`. This way the plugin will always use the first match without checking its target.

### 📱 Setup Your Neovim For iOS Development

I wrote an article that sums up all steps to set up your Neovim from scratch to develop iOS and macOS apps:

[The Complete Guide To iOS & macOS Development In Neovim](https://wojciechkulik.pl/ios/the-complete-guide-to-ios-macos-development-in-neovim)

You can also check out a sample Neovim configuration that I prepared for iOS development: [ios-dev-starter-nvim](https://github.com/wojciech-kulik/ios-dev-starter-nvim)

### 📦 Swift Packages Development

This plugin supports only iOS and macOS applications. However, if you develop Swift Package for one of those platforms, you can easily use this plugin by creating a sample iOS/macOS project in your root directory and adding your package as a dependency.

### 🔬 DAP Integration

[nvim-dap](https://github.com/mfussenegger/nvim-dap) plugin lets you debug applications like in any other IDE. On top of that [nvim-dap-ui](https://github.com/rcarriga/nvim-dap-ui) extension will present for you all panels with stack, breakpoints, variables, logs, etc.

To configure DAP for development:

- Download codelldb VS Code plugin from: [HERE](https://github.com/vadimcn/codelldb/releases). For macOS use `darwin` version. Just unzip `vsix` file and set paths below.
- Install also [nvim-dap-ui](https://github.com/rcarriga/nvim-dap-ui) for a nice GUI to debug.

<details>
  <summary>👉 nvim-dap configuration</summary>

```lua
return {
  "mfussenegger/nvim-dap",
  dependencies = {
    "wojciech-kulik/xcodebuild.nvim"
  },
  config = function()
    local dap = require("dap")
    local xcodebuild = require("xcodebuild.dap")

    dap.configurations.swift = {
      {
        name = "iOS App Debugger",
        type = "codelldb",
        request = "attach",
        program = xcodebuild.get_program_path,
        -- alternatively, you can wait for the process manually
        -- pid = xcodebuild.wait_for_pid,
        cwd = "${workspaceFolder}",
        stopOnEntry = false,
        waitFor = true,
      },
    }

    dap.adapters.codelldb = {
      type = "server",
      port = "13000",
      executable = {
        -- set path to the downloaded codelldb
        -- sample path: "/Users/YOU/Downloads/codelldb-aarch64-darwin/extension/adapter/codelldb"
        command = "/path/to/codelldb/extension/adapter/codelldb",
        args = {
          "--port",
          "13000",
          "--liblldb",
          -- make sure that this path is correct on your side
          "/Applications/Xcode.app/Contents/SharedFrameworks/LLDB.framework/Versions/A/LLDB",
        },
      },
    }

    -- disables annoying warning that requires hitting enter
    local orig_notify = require("dap.utils").notify
    require("dap.utils").notify = function(msg, log_level)
      if not string.find(msg, "Either the adapter is slow") then
        orig_notify(msg, log_level)
      end
    end

    -- sample keymaps to debug application
    vim.keymap.set("n", "<leader>dd", xcodebuild.build_and_debug, { desc = "Build & Debug" })
    vim.keymap.set("n", "<leader>dr", xcodebuild.debug_without_build, { desc = "Debug Without Building" })
  end,
}
```

</details>

## 🚀 Usage

Make sure to open your project's root directory in Neovim and run `XcodebuildSetup` to configure the project. The plugin needs several information like project file, scheme, config, device, and test plan to be able to run commands.

### 🔧 Commands

Xcodebuild.nvim comes with the following commands:

### General

| Command                      | Description                                              |
| ---------------------------- | -------------------------------------------------------- |
| `XcodebuildSetup`            | Run configuration wizard to select project configuration |
| `XcodebuildPicker`           | Show picker with all available actions                   |
| `XcodebuildBuild`            | Build project                                            |
| `XcodebuildCleanBuild`       | Build project (clean build)                              |
| `XcodebuildBuildRun`         | Build & run app                                          |
| `XcodebuildBuildForTesting`  | Build for testing                                        |
| `XcodebuildRun`              | Run app without building                                 |
| `XcodebuildCancel`           | Cancel currently running action                          |
| `XcodebuildCleanDerivedData` | Deletes project's DerivedData                            |
| `XcodebuildToggleLogs`       | Toggle logs panel                                        |
| `XcodebuildOpenLogs`         | Open logs panel                                          |
| `XcodebuildCloseLogs`        | Close logs panel                                         |

### Testing

| Command                      | Description                               |
| ---------------------------- | ----------------------------------------- |
| `XcodebuildTest`             | Run tests (whole test plan)               |
| `XcodebuildTestTarget`       | Run test target (where the cursor is)     |
| `XcodebuildTestClass`        | Run test class (where the cursor is)      |
| `XcodebuildTestFunc`         | Run test (where the cursor is)            |
| `XcodebuildTestSelected`     | Run selected tests (using visual mode)    |
| `XcodebuildTestFailing`      | Rerun previously failed tests             |
| `XcodebuildFailingSnapshots` | Show a picker with failing snapshot tests |

### Code Coverage

| Command                            | Description                                |
| ---------------------------------- | ------------------------------------------ |
| `XcodebuildToggleCodeCoverage`     | Toggle code coverage marks on the side bar |
| `XcodebuildShowCodeCoverageReport` | Open HTML code coverage report             |
| `XcodebuildJumpToNextCoverage`     | Jump to next code coverage mark            |
| `XcodebuildJumpToPrevCoverage`     | Jump to previous code coverage mark        |

### Test Explorer

| Command                                  | Description                    |
| ---------------------------------------- | ------------------------------ |
| `XcodebuildTestExplorerShow`             | Show Test Explorer             |
| `XcodebuildTestExplorerHide`             | Hide Test Explorer             |
| `XcodebuildTestExplorerToggle`           | Toggle Test Explorer           |
| `XcodebuildTestExplorerRunSelectedTests` | Run Selected Tests             |
| `XcodebuildTestExplorerRerunTests`       | Re-run recently selected tests |

### Configuration

| Command                    | Description                         |
| -------------------------- | ----------------------------------- |
| `XcodebuildSelectProject`  | Show project file picker            |
| `XcodebuildSelectScheme`   | Show scheme picker                  |
| `XcodebuildSelectConfig`   | Show build configuration picker     |
| `XcodebuildSelectDevice`   | Show device picker                  |
| `XcodebuildSelectTestPlan` | Show test plan picker               |
| `XcodebuildShowConfig`     | Print current project configuration |
| `XcodebuildBootSimulator`  | Boot selected simulator             |
| `XcodebuildUninstall`      | Uninstall mobile app                |

Sample key bindings:

```lua
-- Lua
vim.keymap.set("n", "<leader>xl", "<cmd>XcodebuildToggleLogs<cr>", { desc = "Toggle Xcodebuild Logs" })
vim.keymap.set("n", "<leader>xb", "<cmd>XcodebuildBuild<cr>", { desc = "Build Project" })
vim.keymap.set("n", "<leader>xr", "<cmd>XcodebuildBuildRun<cr>", { desc = "Build & Run Project" })
vim.keymap.set("n", "<leader>xt", "<cmd>XcodebuildTest<cr>", { desc = "Run Tests" })
vim.keymap.set("v", "<leader>xt", "<cmd>XcodebuildTestSelected<cr>", { desc = "Run Selected Tests" })
vim.keymap.set("n", "<leader>xT", "<cmd>XcodebuildTestClass<cr>", { desc = "Run This Test Class" })
vim.keymap.set("n", "<leader>xf", "<cmd>XcodebuildTestTarget<cr>", { desc = "Run This Test Target" })
vim.keymap.set("n", "<leader>X", "<cmd>XcodebuildPicker<cr>", { desc = "Show All Xcodebuild Actions" })
vim.keymap.set("n", "<leader>xd", "<cmd>XcodebuildSelectDevice<cr>", { desc = "Select Device" })
vim.keymap.set("n", "<leader>xp", "<cmd>XcodebuildSelectTestPlan<cr>", { desc = "Select Test Plan" })
vim.keymap.set("n", "<leader>xs", "<cmd>XcodebuildFailingSnapshots<cr>", { desc = "Show Failing Snapshots" })
vim.keymap.set("n", "<leader>xc", "<cmd>XcodebuildToggleCodeCoverage<cr>", { desc = "Toggle Code Coverage" })
vim.keymap.set("n", "<leader>xC", "<cmd>XcodebuildShowCodeCoverageReport<cr>", { desc = "Show Code Coverage Report" })
vim.keymap.set("n", "<leader>xe", "<cmd>XcodebuildTestExplorerToggle<cr>", { desc = "Toggle Test Explorer" })
vim.keymap.set("n", "[r", "<cmd>XcodebuildJumpToPrevCoverage<cr>", { desc = "Jump To Previous Coverage" })
vim.keymap.set("n", "]r", "<cmd>XcodebuildJumpToNextCoverage<cr>", { desc = "Jump To Next Coverage" })
vim.keymap.set("n", "<leader>xq", "<cmd>Telescope quickfix<cr>", { desc = "Show QuickFix List" })
```

### 📋 Logs Panel Key Bindings

- Press `o` on a failed test in the summary section to jump to the failing location
- Press `q` to close the panel

### 🧪 Test Explorer Key Bindings

- Press `o` to jump to the test implementation
- Press `t` to run selected tests
- Press `T` to re-run recently selected tests
- Press `R` to reload test list
- Press `[` to jump to the previous failed test
- Press `]` to jump to the next failed test
- Press `<cr>` to expand or collapse the current node
- Press `<tab>` to expand or collapse all classes
- Press `q` to close the Test Explorer

### 🚥 Lualine Integration

![Xcodebuild Lualine](./media/lualine.png)

You can also integrate this plugin with [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim).

Sample configuration:

```lua
lualine_x = {
  { "diff" },
  { "'󰙨 ' .. vim.g.xcodebuild_test_plan" },
  { "vim.g.xcodebuild_platform == 'macOS' and '  macOS' or ' ' .. vim.g.xcodebuild_device_name" },
  { "' ' .. vim.g.xcodebuild_os" },
  { "encoding" },
  { "filetype", icon_only = true },
}
```

Global variables that you can use:

| Variable                       | Description                                 |
| ------------------------------ | ------------------------------------------- |
| `vim.g.xcodebuild_device_name` | Device name (ex. iPhone 15 Pro)             |
| `vim.g.xcodebuild_os`          | OS version (ex. 16.4)                       |
| `vim.g.xcodebuild_platform`    | Device platform (macOS or iPhone Simulator) |
| `vim.g.xcodebuild_config`      | Selected build config (ex. Debug)           |
| `vim.g.xcodebuild_scheme`      | Selected project scheme (ex. MyApp)         |
| `vim.g.xcodebuild_test_plan`   | Selected Test Plan (ex. MyAppTests)         |

### 🧪 Code Coverage

![Xcodebuild Code Coverage](./media/code-coverage.png)
![Xcodebuild Code Coverage Report](./media/coverage-report.png)

Using xcodebuild.nvim you can also check the code coverage after running tests.

1. Make sure that you enabled code coverage for desired targets in your test plan.
2. Enable code coverage in xcodebuild [config](#%EF%B8%8F-configuration):

```lua
code_coverage = {
  enabled = true,
}
```

3. Toggle code coverage `:XcodebuildToggleCodeCoverage` or `:lua require("xcodebuild.actions").toggle_code_coverage(true)`.
4. Run tests - once it's finished, code coverage should appear on the sidebar with line numbers.
5. You can jump between code coverage marks using `:XcodebuildJumpToPrevCoverage` and `:XcodebuildJumpToNextCoverage`.
6. You can also check out the report using `:XcodebuildShowCodeCoverageReport` command.

The plugin sends `XcodebuildCoverageToggled` event that you can use to disable other plugins presenting lines on the side bar (like `gitsigns`). Example:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "XcodebuildCoverageToggled",
  callback = function(event)
    local isOn = event.data
    require("gitsigns").toggle_signs(not isOn)
  end,
})
```

Coverage Report Keys:

| Key              | Description                         |
| ---------------- | ----------------------------------- |
| `enter` or `tab` | Expand or collapse the current node |
| `o`              | Open source file                    |

⚠️  From time to time, the code coverage may fail or some targets may be missing (Xcode's bug). Try running tests again then.

⚠️  If you run tests, modify file and toggle code coverage AFTER that, the placement of marks will be incorrect (because it doesn't know about changes that you made). However, if you show code coverage and after that you modify the code, marks will be moving while you are editing the file.

### 📸 Snapshot Tests Preview

This plugin offers a nice list of failing snapshot tests. For each test it generates a preview image combining reference, failure, and difference images into one. It works with [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing) library.

Run `:XcodebuildFailingSnapshots` to see the list.

![Xcodebuild Snapshots](./media/snapshots.png)

### 👨‍💻 API

If you want to use functions directly instead of user commands, then please see [xcodebuild.actions](./lua/xcodebuild/actions.lua) module.

### 🧰 Troubleshooting

Loading project configuration is a very complex task that relies on parsing multiple crazy outputs from `xcodebuild` commands. Those logs are a pure nightmare to parse. It may not always work. In case of any issues with that, you can try manually providing the configuration by adding `.nvim/xcodebuild/settings.json` file in your root directory.

Sample `settings.json`:

```json
{
  "platform": "iOS",
  "testPlan": "UnitTests",
  "config": "Debug",
  "xcodeproj": "/path/to/project/App.xcodeproj",
  "projectFile": "/path/to/project/App.xcworkspace",
  "projectCommand": "-workspace '/path/to/project/App.xcworkspace'",
  "bundleId": "com.company.bundle-id",
  "destination": "00006000-000C58DC1ED8801E",
  "productName": "App",
  "scheme": "App",
  "appPath": "/Users/YOU/Library/Developer/Xcode/DerivedData/App-abafsafasdfasdf/Build/Products/Debug/App.app"
}
```

- `platform` - `macOS` or `iOS`
- `destination` - simulator ID
- `projectFile` / `projectCommand` - can be `xcodeproj` or `xcworkspace`, the main project file that you use
