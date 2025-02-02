---@mod xcodebuild.core.autocmd Autocommands
---@brief [[
---This module is responsible for setting up autocommands.
---It listens to the following events:
---- `VimEnter`: when the user starts Neovim,
---- `BufReadPost`: when a buffer is read.
---
---These events are used to refresh marks and diagnostics.
---@brief ]]

local M = {}

---Setup the autocommands for xcodebuild.nvim
function M.setup()
  local appdata = require("xcodebuild.project.appdata")
  local config = require("xcodebuild.core.config").options
  local projectConfig = require("xcodebuild.project.config")
  local projectManager = require("xcodebuild.project.manager")
  local diagnostics = require("xcodebuild.tests.diagnostics")
  local logsPanel = require("xcodebuild.xcode_logs.panel")
  local coverage = require("xcodebuild.code_coverage.coverage")
  local events = require("xcodebuild.broadcasting.events")
  local autogroup = vim.api.nvim_create_augroup("xcodebuild.nvim", { clear = true })

  if config.restore_on_start then
    vim.api.nvim_create_autocmd({ "VimEnter" }, {
      group = autogroup,
      pattern = "*",
      once = true,
      callback = appdata.load_last_report,
    })
  end

  vim.api.nvim_create_autocmd({ "BufReadPost" }, {
    group = autogroup,
    pattern = "*" .. appdata.build_logs_filename,
    callback = function(ev)
      logsPanel.setup_buffer(ev.buf)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufReadPost" }, {
    group = autogroup,
    pattern = "*.swiftinterface",
    command = "set filetype=swift",
  })

  if config.guess_scheme then
    vim.api.nvim_create_autocmd({ "BufEnter" }, {
      group = autogroup,
      pattern = "*.swift",
      callback = function()
        projectManager.update_current_file_scheme()
      end,
    })
  end

  if config.marks.show_diagnostics or config.marks.show_signs then
    vim.api.nvim_create_autocmd({ "BufReadPost" }, {
      group = autogroup,
      pattern = "*.swift",
      callback = function(ev)
        if projectConfig.is_configured() and appdata.report and appdata.report.tests then
          local filepath = vim.api.nvim_buf_get_name(ev.buf)

          -- refresh diagnostics if the file is in the report
          for _, testClass in pairs(appdata.report.tests) do
            for _, test in ipairs(testClass) do
              if test.filepath == filepath then
                diagnostics.refresh_test_buffer(ev.buf, appdata.report)
                break
              end
            end
          end
        end
      end,
    })
  end

  if config.code_coverage.enabled then
    vim.api.nvim_create_autocmd({ "BufReadPost" }, {
      group = autogroup,
      pattern = config.code_coverage.file_pattern,
      callback = function(ev)
        coverage.show_coverage(ev.buf)
      end,
    })

    vim.api.nvim_create_autocmd({ "BufReadPost" }, {
      group = autogroup,
      pattern = config.code_coverage.file_pattern,
      once = true,
      callback = function()
        projectConfig.load_settings()

        if coverage.is_code_coverage_available() and projectConfig.settings.showCoverage then
          events.toggled_code_coverage(true)
        end
      end,
    })
  end
end

return M
