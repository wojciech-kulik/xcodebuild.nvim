# 🛠️ xcodebuild.nvim

A plugin designed to let you migrate your app development from Xcode to Neovim.
It provides all essential actions for development including building, debugging, and testing.

<img src="./media/testing.png" style="border-radius: 8px;" alt="xcodebuild.nvim - unit tests" />
&nbsp;
<img src="./media/debugging.png" style="border-radius: 8px;" alt="xcodebuild.nvim - debugging" />

## ✨  Features

- [x] Support for iOS, iPadOS, watchOS, tvOS, visionOS, and macOS.
- [x] Project-based configuration.
- [x] Project Manager to deal with project files without using Xcode.
- [x] Test Explorer to visually present a tree with all tests and results.
- [x] Built using official command line tools like `xcodebuild` and `xcrun simctl`.
- [x] Actions to build, run, debug, and test apps on simulators and physical devices.
- [x] Buffer integration with test results (code coverage, success & failure marks, duration,
      extra diagnostics).
- [x] Code coverage report with customizable levels.
- [x] Advanced log parser to detect all errors, warnings, and failing tests.
- [x] [nvim-tree], [neo-tree], and [oil.nvim] integration that automatically reflects
      all file tree operations and updates Xcode project.
- [x] [nvim-dap] integration to let you easily build, run, and debug apps.
- [x] [nvim-dap-ui] integration to show app logs in the console window.
- [x] [lualine.nvim] integration to show selected device, test plan, and other project settings.
- [x] [swift-snapshot-testing] integration to present diff views for failing snapshot tests.
- [x] [Quick] integration to show test results for tests written using [Quick] framework.
- [x] Auto-detection of the target membership for new files.
- [x] Picker with all available plugin actions.
- [x] Highly customizable (many config options, auto commands, highlights, and user commands).

## 📦  Installation

Read [Wiki] to learn how to install and configure the plugin.

## 📚  Documentation

Everything about the plugin is described in the [Wiki]. You can find there all available commands,
integrations, settings, and examples.

## 🎥  Demo

### Testing

xcodebuild.nvim supports code coverage, test explorer, diagnostics, snapshot tests, Quick framework, and more! 

https://github.com/user-attachments/assets/30da2636-34e1-4940-b1f9-d422ccb7ff46

### Working With Code

Neovim can be easily integrated with SwiftLint, SwiftFormat, Copilot, and more.
In the video, you can see basic navigation, diagnostics, formatting, linting, code completion, and of course, 
launching the app on a simulator. 

https://github.com/user-attachments/assets/2b44ad01-a736-42ba-b5aa-be0ecaea5a29

### Debugging

The plugin allows you to debug both on simulators and physical devices. You get access to all basic things like breakpoints,
variables inspection, call stack, lldb, etc. You can even see app logs. 

https://github.com/user-attachments/assets/a2b87eab-5cdc-4fe5-8f96-78bc1a21e924

&nbsp;

[Wiki]: https://github.com/wojciech-kulik/xcodebuild.nvim/wiki
[nvim-tree]: https://github.com/nvim-tree/nvim-tree.lua
[neo-tree]: https://github.com/nvim-neo-tree/neo-tree.nvim
[oil.nvim]: https://github.com/stevearc/oil.nvim
[nvim-dap]: https://github.com/mfussenegger/nvim-dap
[nvim-dap-ui]: https://github.com/rcarriga/nvim-dap-ui
[nvim-treesitter]: https://github.com/nvim-treesitter/nvim-treesitter
[swift-snapshot-testing]: https://github.com/pointfreeco/swift-snapshot-testing
[Quick]: https://github.com/Quick/Quick
[lualine.nvim]: https://github.com/nvim-lualine/lualine.nvim
