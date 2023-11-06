# 🛠️ xcodebuild.nvim

A plugin that lets you move your iOS, iPadOS and macOS apps development to Neovim. It supports most of Xcode actions that are required to work with a project, like device selection, building, launching, and testing.

![Xcodebuild Debugging](./media/tests.png)

![Xcodebuild Testing](./media/debug.png)

## 🚧 Disclaimer

This plugin is in early stage of development. It was tested on a limited number of projects and configurations. Therefore, it still could be buggy. If you find any issues don't hesitate to fix it and create a pull request or just report them.

It is also my first Neovim plugin. Hopefully, a good one 😁.

I've been looking for a solution to move my development to any other IDE than Xcode for a long time. It seems that this plugin + [nvim-dap](https://github.com/mfussenegger/nvim-dap) + [nvim-dap-ui](https://github.com/rcarriga/nvim-dap-ui) + [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) + [xcode-build-server](https://github.com/SolaWing/xcode-build-server), all together, provide everything that is needed to move to Neovim with iOS, iPadOS, and macOS apps development.

Of course, you will still need Xcode for some project setup & management. Also, you may need to migrate to [tuist](https://github.com/tuist/tuist) or [xcodegen](https://github.com/yonaskolb/XcodeGen) to be able to add new files easily.

## ✨ Features

- [x] Support for iOS, iPadOS, and macOS apps.
- [x] Project-based configuration.
- [x] Configuration wizard to setup: project file, scheme, test plan, and device.
- [x] Built based on core command line tools like `xcodebuild` and `xcrun simctl`. It doesn't require any external tools, only `xcbeautify` to format logs, but it could be changed in configuration.
- [x] Build, run and test actions.
- [x] App deployment to selected iOS simulator.
- [x] Uninstall mobile app.
- [x] Running only selected tests (one test, one class, selected tests in visual mode, whole test plan).
- [x] Showing icons with test result next to each test.
- [x] Showing test duration next to each test.
- [x] Showing test errors in diagnostics and on the quickfix list.
- [x] Showing build errors and warnings on the quickfix list.
- [x] Advanced log parser to detect all errors, warnings, and failing tests to present them nicely formatted.
- [x] Auto saving files before build or test actions.
- [x] [nvim-dap](https://github.com/mfussenegger/nvim-dap) helper function to let you easily build, run, and attach the debugger.
- [x] [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) integration to show pickers with selectable project options.
- [x] Picker with all available actions.

## 👷 Limitations

The plugin assumes that test class name should match file name. If in logs `YourTraget.YourTestClass.testYourTest` appears, the plugin is trying to locate `YourTestClass.swift` file and show test results there (marks + diagnostics + quickfix).

If you have a different naming convention, or if you have multiple test classes named the same across the project, it may not work correctly.

I will try to address it as soon as possible, but for now there is this limitation.

## ⚡️ Requirements

- [Neovim](https://neovim.io) (not sure which version, use the new one :D).
- [xcbeautify](https://github.com/tuist/xcbeautify) tool (`brew install xcbeautify`) or just turn it off in config.
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) to present all pickers by the plugin.
- Xcode (make sure that `xcodebuild` and `xcrun simctl` work correctly).
- To get the best experience with apps development, you should install and configure [nvim-dap](https://github.com/mfussenegger/nvim-dap) and [nvim-dap-ui](https://github.com/rcarriga/nvim-dap-ui) to be able to debug.
- This plugin requires the project to be written in Swift. It was tested only with Xcode 15.
- [lsp-trouble.nvim](https://github.com/simrat39/lsp-trouble.nvim) - if you want to see all issues nicely presented, you can use it with `quickfix` mode.
- Make sure to configure LSP properly for iOS/macOS apps. You can read how to do that in my post: [How to develop iOS and macOS apps in Neovim?](https://wojciechkulik.pl/ios/how-to-develop-ios-and-macos-apps-in-other-ides-like-neovim-or-vs-code).

## 📦 Installation

Install the plugin with your preferred package manager:

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
return {
  "wojciech-kulik/xcodebuild.nvim",
  dependencies = { "nvim-telescope/telescope.nvim" },
  config = function()
    require("xcodebuild").setup({
        -- put some options here or leave it empty to use default settings
    })
  end,
}
```

## ⚙️ Configuration

### Setup

Xcodebuild.nvim comes with the following defaults:

```lua
{
  restore_on_start = true, -- logs, diagnostics, and marks will be loaded on VimEnter (may affect performance)
  auto_save = true, -- save all buffers before running build or tests (command: silent wa!)
  logs = {
    auto_open_on_success_tests = true, -- open logs when tests succeeded
    auto_open_on_failed_tests = true, -- open logs when tests failed
    auto_open_on_success_build = true, -- pen logs when build succeeded
    auto_open_on_failed_build = true, -- open logs when build failed
    auto_focus = true, -- focus logs buffer when opened
    open_command = "silent bo split {path} | resize 20", -- command used to open logs panel. You must use {path} variable to load the log file
    logs_formatter = "xcbeautify --disable-colored-output", -- command used to format logs, you can use nil to skip formatting
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
    show_errors_on_quickfixlist = true, -- add errors to quickfix list
    show_warnings_on_quickfixlist = true, -- add build warnings to quickfix list
  },
}
```

### DAP Integration

[nvim-dap](https://github.com/mfussenegger/nvim-dap) plugin let's you debug applications like in any other IDE. On top of that [nvim-dap-ui](https://github.com/rcarriga/nvim-dap-ui) extension will present for you all panels with stack, breakpoints, variables, logs, etc.

To configure DAP for development:

- Download codelldb VS Code plugin from: [HERE](https://github.com/vadimcn/codelldb/releases). For macOS use `darwin` version. Just unzip `vsix` file and set paths below.
- Install also [nvim-dap-ui](https://github.com/rcarriga/nvim-dap-ui) for a nice GUI to debug.

```lua
return {
  "mfussenegger/nvim-dap",
    dependencies = {
        "wojciech-kulik/xcodebuild.nvim"
    },
  config = function()
    local dap = require("dap")

    dap.configurations.swift = {
      {
        name = "iOS App Debugger",
        type = "codelldb",
        request = "attach",
                -- this will wait until the app is launched
        pid = require("xcodebuild.dap").wait_for_pid,
        cwd = "${workspaceFolder}",
        stopOnEntry = false,
      },
    }

    dap.adapters.codelldb = {
      type = "server",
      port = "13000",
      executable = {
                -- set path to the downloaded codelldb
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

        -- sample keymap to build & run the app
    vim.keymap.set("n", "<leader>R", function()
      require("xcodebuild.dap").build_and_run(function()
        dap.continue()
      end)
    end)
    end,
}
```

## 🚀 Usage

Make sure to open your project's root directory in Neovim and run `XcodebuildSetup` to configure the project. The plugin needs several information like project file, scheme, device, and test plan to be able to run commands.

### Commands

Xcodebuild.nvim comes with the following commands:

| Command                    | Description                                              |
| -------------------------- | -------------------------------------------------------- |
| `XcodebuildSetup`          | Run configuration wizard to select project configuration |
| `XcodebuildPicker`         | Show picker with all available actions                   |
| `XcodebuildBuild`          | Build project                                            |
| `XcodebuildBuildRun`       | Build & run app                                          |
| `XcodebuildRun`            | Run app without building                                 |
| `XcodebuildCancel`         | Cancel currently running action                          |
| `XcodebuildTest`           | Run tests (whole test plan)                              |
| `XcodebuildTestClass`      | Run test class (where the cursor is)                     |
| `XcodebuildTestFunc`       | Run test (where the cursor is)                           |
| `XcodebuildTestSelected`   | Run selected tests (using visual mode)                   |
| `XcodebuildTestFailing`    | Rerun previously failed tests                            |
| `XcodebuildSelectProject`  | Show picker with project file selection                  |
| `XcodebuildSelectScheme`   | Show picker with scheme selection                        |
| `XcodebuildSelectConfig`   | Show picker with build configuration selection           |
| `XcodebuildSelectDevice`   | Show picker with device selection                        |
| `XcodebuildSelectTestPlan` | Show picker with test plan selection                     |
| `XcodebuildToggleLogs`     | Toggle logs panel                                        |
| `XcodebuildOpenLogs`       | Open logs panel                                          |
| `XcodebuildCloseLogs`      | Close logs panel                                         |
| `XcodebuildUninstall`      | Uninstall mobile app                                     |

Sample key bindings:

```lua
-- Lua
vim.keymap.set("n", "<leader>xl", "<cmd>XcodebuildToggleLogs<cr>", { desc = "Toggle Xcodebuild Logs" })
vim.keymap.set("n", "<leader>xb", "<cmd>XcodebuildBuild<cr>", { desc = "Build Project" })
vim.keymap.set("n", "<leader>xr", "<cmd>XcodebuildBuildRun<cr>", { desc = "Build & Run Project" })
vim.keymap.set("n", "<leader>xt", "<cmd>XcodebuildTest<cr>", { desc = "Run Tests" })
vim.keymap.set("n", "<leader>xT", "<cmd>XcodebuildTestClass<cr>", { desc = "Run This Test Class" })
vim.keymap.set("n", "<leader>X", "<cmd>XcodebuildPicker<cr>", { desc = "Show All Xcodebuild Actions" })
vim.keymap.set("n", "<leader>xd", "<cmd>XcodebuildSelectDevice<cr>", { desc = "Select Device" })
vim.keymap.set("n", "<leader>xp", "<cmd>XcodebuildSelectTestPlan<cr>", { desc = "Select Test Plan" })
vim.keymap.set("n", "<leader>xq", "<cmd>Telescope quickfix<cr>", { desc = "Show QuickFix List" })
```

### API

If you want to use functions directly instead of user commands, then please see [xcodebuild.actions](./lua/xcodebuild/actions.lua) module.
