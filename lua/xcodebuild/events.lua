local M = {}

local lastDuration = 0

-- Build

function M.build_started(forTesting)
  vim.api.nvim_exec_autocmds("User", {
    pattern = "XcodebuildBuildStarted",
    data = { forTesting = forTesting },
  })

  vim.g.xcodebuild_last_status = nil
end

function M.build_status(forTesting, progress, duration)
  vim.api.nvim_exec_autocmds("User", {
    pattern = "XcodebuildBuildStatus",
    data = { forTesting = forTesting, progress = progress, duration = duration },
  })
  lastDuration = duration
end

function M.build_finished(forTesting, success, cancelled, errors)
  vim.api.nvim_exec_autocmds("User", {
    pattern = "XcodebuildBuildFinished",
    data = { forTesting = forTesting, success = success, cancelled = cancelled, errors = errors },
  })

  if cancelled then
    vim.g.xcodebuild_last_status = "Build Cancelled"
  elseif success then
    vim.g.xcodebuild_last_status = "Build Succeeded [" .. lastDuration .. "s]"
  else
    vim.g.xcodebuild_last_status = "Build Failed with " .. #errors .. " error(s)"
  end
end

-- Tests

function M.tests_started()
  vim.api.nvim_exec_autocmds("User", {
    pattern = "XcodebuildTestsStarted",
  })

  vim.g.xcodebuild_last_status = nil
end

function M.tests_status(passedCount, failedCount)
  vim.api.nvim_exec_autocmds("User", {
    pattern = "XcodebuildTestsStatus",
    data = { passedCount = passedCount, failedCount = failedCount },
  })
end

function M.tests_finished(passedCount, failedCount, cancelled)
  vim.api.nvim_exec_autocmds("User", {
    pattern = "XcodebuildTestsFinished",
    data = { passedCount = passedCount, failedCount = failedCount, cancelled = cancelled },
  })

  local success = failedCount == 0

  if cancelled then
    vim.g.xcodebuild_last_status = "Tests Cancelled"
  elseif success then
    vim.g.xcodebuild_last_status = "Tests Passed [Executed: " .. passedCount .. "]"
  else
    vim.g.xcodebuild_last_status = "Tests Failed [Passed: "
      .. passedCount
      .. " Failed: "
      .. failedCount
      .. "]"
  end
end

-- Other

function M.application_launched()
  vim.api.nvim_exec_autocmds("User", {
    pattern = "XcodebuildApplicationLaunched",
  })
end

function M.action_cancelled()
  vim.api.nvim_exec_autocmds("User", {
    pattern = "XcodebuildActionCancelled",
  })
end

function M.project_settings_updated(settings)
  vim.api.nvim_exec_autocmds("User", {
    pattern = "XcodebuildProjectSettingsUpdated",
    data = settings,
  })
end

-- Panels

function M.toggled_test_explorer(visible, bufnr, winnr)
  vim.api.nvim_exec_autocmds("User", {
    pattern = "XcodebuildTestExplorerToggled",
    data = { visible = visible, bufnr = bufnr, winnr = winnr },
  })
end

function M.toggled_code_coverage(visible)
  vim.api.nvim_exec_autocmds("User", {
    pattern = "XcodebuildCoverageToggled",
    data = visible,
  })
end

function M.toggled_code_coverage_report(visible, bufnr, winnr)
  vim.api.nvim_exec_autocmds("User", {
    pattern = "XcodebuildCoverageReportToggled",
    data = { visible = visible, bufnr = bufnr, winnr = winnr },
  })
end

function M.toggled_logs(visible, bufnr, winnr)
  vim.api.nvim_exec_autocmds("User", {
    pattern = "XcodebuildLogsToggled",
    data = { visible = visible, bufnr = bufnr, winnr = winnr },
  })
end

return M
