local notifications = require("xcodebuild.notifications")
local util = require("xcodebuild.util")
local projectConfig = require("xcodebuild.project_config")
local xcode = require("xcodebuild.xcode")
local projectBuilder = require("xcodebuild.project_builder")
local simulator = require("xcodebuild.simulator")

local M = {}

function M.build_and_debug(callback)
  local loadedDap, dap = pcall(require, "dap")
  if not loadedDap then
    error("Could not load dap plugin")
    return
  end

  xcode.kill_app(projectConfig.settings.productName)
  dap.continue()

  projectBuilder.build_project({}, function(report)
    local success = util.is_empty(report.buildErrors)

    if success then
      simulator.run_app(false, callback)
    else
      dap.terminate()

      local loadedDapui, dapui = pcall(require, "dapui")
      if loadedDapui then
        dapui.close()
      end
    end
  end)
end

function M.debug_without_build(callback)
  local loadedDap, dap = pcall(require, "dap")
  if not loadedDap then
    error("Could not load dap plugin")
    return
  end

  xcode.kill_app(projectConfig.settings.productName)
  dap.continue()
  simulator.run_app(false, callback)
end

function M.get_program_path()
  if projectConfig.settings.platform == "macOS" then
    return projectConfig.settings.appPath .. "/Contents/MacOS/" .. projectConfig.settings.productName
  else
    return projectConfig.settings.appPath
  end
end

function M.wait_for_pid()
  local co = coroutine
  local productName = projectConfig.settings.productName

  if not productName then
    error("You must build the application first")
  end

  return co.create(function(dap_run_co)
    local pid = nil

    notifications.send("Attaching debugger...")
    for _ = 1, 10 do
      util.shell("sleep 1")
      pid = xcode.get_app_pid(productName)

      if tonumber(pid) then
        break
      end
    end

    if not tonumber(pid) then
      notifications.send_error("Launching the application timed out")

      ---@diagnostic disable-next-line: deprecated
      co.close(dap_run_co)
    end

    co.resume(dap_run_co, pid)
  end)
end

function M.clear_console()
  local success, dapui = pcall(require, "dapui")
  if not success then
    return
  end

  local bufnr = dapui.elements.console.buffer()
  if not bufnr then
    return
  end

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})
  vim.bo[bufnr].modified = false
  vim.bo[bufnr].modifiable = false
end

function M.update_console(output)
  local success, dapui = pcall(require, "dapui")
  if not success then
    return
  end

  local bufnr = dapui.elements.console.buffer()
  if not bufnr then
    return
  end

  if util.is_empty(output) then
    return
  end

  vim.bo[bufnr].modifiable = true

  local autoscroll = false
  local winnr = vim.fn.win_findbuf(bufnr)[1]
  if winnr then
    local currentWinnr = vim.api.nvim_get_current_win()
    local lastLine = vim.api.nvim_buf_line_count(bufnr)
    local currentLine = vim.api.nvim_win_get_cursor(winnr)[1]
    autoscroll = currentWinnr ~= winnr or currentLine == lastLine
  end

  vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, output)

  if autoscroll then
    vim.api.nvim_win_call(winnr, function()
      vim.cmd("normal! G")
    end)
  end

  vim.bo[bufnr].modified = false
  vim.bo[bufnr].modifiable = false
end

return M
