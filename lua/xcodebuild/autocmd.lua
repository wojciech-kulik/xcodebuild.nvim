local M = {}

function M.setup()
  local appdata = require("xcodebuild.appdata")
  local coordinator = require("xcodebuild.coordinator")
  local config = require("xcodebuild.config").options
  local projectConfig = require("xcodebuild.project_config")
  local diagnostics = require("xcodebuild.diagnostics")
  local logs = require("xcodebuild.logs")
  local coverage = require("xcodebuild.coverage")
  local autogroup = vim.api.nvim_create_augroup("xcodebuild.nvim", { clear = true })

  vim.api.nvim_create_autocmd({ "BufReadPost" }, {
    group = autogroup,
    pattern = "*" .. appdata.build_logs_filename,
    callback = function(ev)
      logs.setup_buffer(ev.buf)
    end,
  })

  if config.restore_on_start then
    vim.api.nvim_create_autocmd({ "VimEnter" }, {
      group = autogroup,
      pattern = "*",
      once = true,
      callback = coordinator.load_last_report,
    })
  end

  if config.marks.show_diagnostics or config.marks.show_signs then
    vim.api.nvim_create_autocmd({ "BufReadPost" }, {
      group = autogroup,
      pattern = config.marks.file_pattern,
      callback = function(ev)
        diagnostics.refresh_test_buffer(ev.buf, coordinator.report)
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

        if coverage.is_code_coverage_available() and projectConfig.settings.show_coverage then
          vim.api.nvim_exec_autocmds("User", {
            pattern = "XcodebuildCoverageToggled",
            data = true,
          })
        end
      end,
    })
  end
end

return M
