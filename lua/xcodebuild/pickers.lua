local xcode = require("xcodebuild.xcode")
local projectConfig = require("xcodebuild.project_config")
local util = require("xcodebuild.util")
local notifications = require("xcodebuild.notifications")
local snapshots = require("xcodebuild.snapshots")

local telescopePickers = require("telescope.pickers")
local telescopeFinders = require("telescope.finders")
local telescopeConfig = require("telescope.config").values
local telescopeActions = require("telescope.actions")
local telescopeState = require("telescope.actions.state")

local M = {}

local currentJobId = nil
local activePicker = nil
local progressTimer = nil
local currentProgressFrame = 1
local progressFrames = {
  "[      ]",
  "[ .    ]",
  "[ ..   ]",
  "[ ...  ]",
  "[  ... ]",
  "[   .. ]",
  "[    . ]",
}

local function stop_telescope_spinner()
  if progressTimer then
    vim.fn.timer_stop(progressTimer)
    progressTimer = nil
  end
end

local function update_telescope_spinner()
  if activePicker and vim.api.nvim_win_is_valid(activePicker.results_win) then
    currentProgressFrame = currentProgressFrame >= #progressFrames and 1 or currentProgressFrame + 1
    activePicker:change_prompt_prefix(progressFrames[currentProgressFrame] .. " ", "TelescopePromptPrefix")
  else
    stop_telescope_spinner()
  end
end

local function start_telescope_spinner()
  if not progressTimer then
    progressTimer = vim.fn.timer_start(80, update_telescope_spinner, { ["repeat"] = -1 })
  end
end

local function update_results(results)
  if currentJobId == nil then
    return
  end

  stop_telescope_spinner()

  if activePicker then
    activePicker:refresh(
      telescopeFinders.new_table({
        results = results,
      }),
      {
        new_prefix = telescopeConfig.prompt_prefix,
      }
    )
  end
end

function M.show(title, items, callback, opts)
  if currentJobId then
    vim.fn.jobstop(currentJobId)
    currentJobId = nil
  end

  activePicker = telescopePickers.new(require("telescope.themes").get_dropdown({}), {
    prompt_title = title,
    finder = telescopeFinders.new_table({
      results = items,
    }),
    sorter = telescopeConfig.generic_sorter(),
    attach_mappings = function(prompt_bufnr, _)
      telescopeActions.select_default:replace(function()
        local selection = telescopeState.get_selected_entry()

        if opts and opts.close_on_select and selection then
          telescopeActions.close(prompt_bufnr)
        end

        if callback and selection then
          callback(selection[1], selection.index)
        end
      end)
      return true
    end,
  })

  activePicker:find()
end

function M.select_project(callback, opts)
  local sanitizedFiles = {}
  local filenames = {}
  local files = util.shell(
    "find '"
      .. vim.fn.getcwd()
      .. "' \\( -iname '*.xcodeproj' -o -iname '*.xcworkspace' \\)"
      .. " -not -path '*/.*' -not -path '*xcodeproj/project.xcworkspace'"
  )

  for _, file in ipairs(files) do
    if util.trim(file) ~= "" then
      table.insert(sanitizedFiles, file)
      table.insert(filenames, string.match(file, ".*%/([^/]*)$"))
    end
  end

  M.show("Select Project/Workspace", filenames, function(_, index)
    local projectFile = sanitizedFiles[index]
    local isWorkspace = util.has_suffix(projectFile, "xcworkspace")

    projectConfig.settings.projectFile = projectFile
    projectConfig.settings.projectCommand = (isWorkspace and "-workspace '" or "-project '")
      .. projectFile
      .. "'"
    projectConfig.save_settings()

    if callback then
      callback(projectFile)
    end
  end, opts)
end

function M.select_scheme(schemes, callback, opts)
  if util.is_empty(schemes) then
    start_telescope_spinner()
  end

  M.show("Select Scheme", schemes, function(value, _)
    projectConfig.settings.scheme = value
    projectConfig.save_settings()

    if callback then
      callback(value)
    end
  end, opts)

  if util.is_empty(schemes) then
    local projectCommand = projectConfig.settings.projectCommand
    currentJobId = xcode.get_project_information(projectCommand, function(info)
      update_results(info.schemes)
    end)

    return currentJobId
  end
end

function M.select_config(callback, opts)
  local projectCommand = projectConfig.settings.projectCommand
  local projectInfo = nil

  start_telescope_spinner()
  M.show("Select Build Configuration", {}, function(value, _)
    projectConfig.settings.config = value
    projectConfig.save_settings()

    if callback then
      callback(projectInfo)
    end
  end, opts)

  currentJobId = xcode.get_project_information(projectCommand, function(info)
    projectInfo = info
    update_results(info.configs)
  end)

  return currentJobId
end

function M.select_testplan(callback, opts)
  local projectCommand = projectConfig.settings.projectCommand
  local scheme = projectConfig.settings.scheme

  start_telescope_spinner()
  M.show("Select Test Plan", {}, function(value, _)
    projectConfig.settings.testPlan = value
    projectConfig.save_settings()

    if callback then
      callback(value)
    end
  end, opts)

  currentJobId = xcode.get_testplans(projectCommand, scheme, function(testPlans)
    if currentJobId and util.is_empty(testPlans) then
      vim.defer_fn(function()
        notifications.send_warning("Could not detect test plans")
      end, 100)

      if activePicker and util.is_not_empty(vim.fn.win_findbuf(activePicker.prompt_bufnr)) then
        telescopeActions.close(activePicker.prompt_bufnr)
      end

      if callback then
        callback()
      end
    else
      update_results(testPlans)
    end
  end)

  return currentJobId
end

function M.select_destination(callback, opts)
  local projectCommand = projectConfig.settings.projectCommand
  local scheme = projectConfig.settings.scheme
  local results = {}

  start_telescope_spinner()
  M.show("Select Device", {}, function(_, index)
    projectConfig.settings.destination = results[index].id
    projectConfig.settings.platform = results[index].platform
    projectConfig.save_settings()

    if callback then
      callback(results[index])
    end
  end, opts)

  currentJobId = xcode.get_destinations(projectCommand, scheme, function(destinations)
    local filtered = util.filter(destinations, function(table)
      return table.id ~= nil
        and table.platform ~= "iOS"
        and (not table.name or not string.find(table.name, "^Any"))
    end)

    local destinationNames = util.select(filtered, function(table)
      local name = table.name or ""
      if table.platform and table.platform ~= "iOS Simulator" then
        name = util.trim(name .. " " .. table.platform)
      end
      if table.platform == "macOS" and table.arch then
        name = name .. " (" .. table.arch .. ")"
      end
      if table.os then
        name = name .. " (" .. table.os .. ")"
      end
      if table.variant then
        name = name .. " (" .. table.variant .. ")"
      end
      if table.error then
        name = name .. " [error]"
      end
      return name
    end)

    results = filtered
    update_results(destinationNames)
  end)

  return currentJobId
end

function M.select_failing_snapshot_test()
  local snapshots = require("xcodebuild.snapshots")
  local failingSnapshots = snapshots.get_failing_snapshots()
  local filenames = util.select(failingSnapshots, function(item)
    return util.get_filename(item)
  end)

  require("xcodebuild.pickers").show("Failing Snapshot Tests", filenames, function(_, index)
    local selectedFile = failingSnapshots[index]
    vim.fn.jobstart("qlmanage -p '" .. selectedFile .. "'", {
      detach = true,
      on_exit = function() end,
    })
  end)
end

function M.show_all_actions()
  local actions = require("xcodebuild.actions")
  local actionsNames = {
    "Build Project",
    "Build & Run Project",
    "Run Without Building",
    "Cancel Running Action",

    "Run Test Plan (all tests)",
    "Run This Test Class",
    "Run This Test",
    "Run Selected Tests",
    "Run Failed Tests",

    "Select Project File",
    "Select Scheme",
    "Select Build Configuration",
    "Select Device",
    "Select Test Plan",

    "Toggle Logs",
    "Open Logs",
    "Close Logs",

    "Show Current Configuration",
    "Show Configuration Wizard",
    "Boot Selected Simulator",
    "Uninstall Application",
  }
  local actionsPointers = {
    actions.build,
    actions.build_and_run,
    actions.run,
    actions.cancel,

    actions.run_tests,
    actions.run_class_tests,
    actions.run_func_test,
    actions.run_selected_tests,
    actions.run_failing_tests,

    actions.select_project,
    actions.select_scheme,
    actions.select_config,
    actions.select_device,
    actions.select_testplan,

    actions.toggle_logs,
    actions.open_logs,
    actions.close_logs,

    actions.show_current_config,
    actions.configure_project,
    actions.boot_simulator,
    actions.uninstall,
  }

  if not projectConfig.is_project_configured() then
    actionsNames = { "Show Configuration Wizard " }
    actionsPointers = { actions.configure_project }
  end

  if require("xcodebuild.config").options.prepare_snapshot_test_previews then
    if #snapshots.get_failing_snapshots() > 0 then
      table.insert(actionsNames, 10, "Preview Failing Snapshot Tests")
      table.insert(actionsPointers, 10, actions.show_failing_snapshot_tests)
    end
  end

  M.show("Xcodebuild Actions", actionsNames, function(_, index)
    if index > 9 or #actionsNames == 1 then
      actionsPointers[index]()
    else
      vim.defer_fn(actionsPointers[index], 100)
    end
  end, { close_on_select = true })
end

return M
