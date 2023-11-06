local appdata = require("xcodebuild.appdata")
local coordinator = require("xcodebuild.coordinator")
local config = require("xcodebuild.config").options

local M = {}
local autogroup = vim.api.nvim_create_augroup("xcodebuild.nvim", { clear = true })

function M.setup()
  vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
    group = autogroup,
    pattern = "*" .. appdata.get_build_logs_filename(),
    callback = function(ev)
      coordinator.setup_log_buffer(ev.buf)
    end,
  })

  if config.restore_on_start then
    vim.api.nvim_create_autocmd({ "VimEnter" }, {
      group = autogroup,
      pattern = "*",
      once = true,
      callback = function()
        coordinator.load_last_report()
      end,
    })
  end

  if config.marks.show_diagnostics or config.marks.show_signs then
    vim.api.nvim_create_autocmd({ "BufReadPost", "BufWritePost" }, {
      group = autogroup,
      pattern = config.marks.file_pattern,
      callback = function(ev)
        coordinator.refresh_buf_diagnostics(ev.buf, ev.file)
      end,
    })
  end
end

return M
