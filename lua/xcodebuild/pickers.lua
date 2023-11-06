local xcode = require("xcodebuild.xcode")
local projectConfig = require("xcodebuild.project_config")
local util = require("xcodebuild.util")

local telescopePickers = require("telescope.pickers")
local telescopeFinders = require("telescope.finders")
local telescopeConfig = require("telescope.config").values
local telescopeActions = require("telescope.actions")
local telescopeState = require("telescope.actions.state")

local M = {}

local active_picker = nil
local anim_timer = nil
local current_frame = 1
local spinner_anim_frames = {
  "[      ]",
  "[ .    ]",
  "[ ..   ]",
  "[ ...  ]",
  "[  ... ]",
  "[   .. ]",
  "[    . ]",
}

local function stop_telescope_spinner()
  if anim_timer then
    vim.fn.timer_stop(anim_timer)
    anim_timer = nil
  end
end

local function update_telescope_spinner()
  if active_picker then
    current_frame = current_frame >= #spinner_anim_frames and 1 or current_frame + 1
    active_picker:change_prompt_prefix(spinner_anim_frames[current_frame] .. " ", "TelescopePromptPrefix")

    if not vim.api.nvim_win_is_valid(active_picker.results_win) then
      stop_telescope_spinner()
    end
  else
    stop_telescope_spinner()
  end
end

local function start_telescope_spinner()
  if not anim_timer then
    anim_timer = vim.fn.timer_start(80, update_telescope_spinner, { ["repeat"] = -1 })
  end
end

local function update_results(results)
  stop_telescope_spinner()

  if active_picker then
    active_picker:refresh(
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
  active_picker = telescopePickers.new(require("telescope.themes").get_dropdown({}), {
    prompt_title = title,
    finder = telescopeFinders.new_table({
      results = items,
    }),
    sorter = telescopeConfig.generic_sorter(),
    attach_mappings = function(prompt_bufnr, _)
      telescopeActions.select_default:replace(function()
        if opts and opts.close_on_select then
          telescopeActions.close(prompt_bufnr)
        end

        local selection = telescopeState.get_selected_entry()
        if callback and selection then
          callback(selection[1], selection.index)
        end
      end)
      return true
    end,
  })

  active_picker:find()
end

function M.select_project(callback, opts)
  local files = util.shell(
    "find '"
      .. vim.fn.getcwd()
      .. "' \\( -iname '*.xcodeproj' -o -iname '*.xcworkspace' \\) -not -path '*/.*' -not -path '*xcodeproj/project.xcworkspace'"
  )
  local sanitizedFiles = {}

  for _, file in ipairs(files) do
    if util.trim(file) ~= "" then
      table.insert(sanitizedFiles, {
        filepath = file,
        name = string.match(file, ".*%/([^/]*)$"),
      })
    end
  end

  local filenames = util.select(sanitizedFiles, function(table)
    return table.name
  end)

  M.show("Select Project/Workspace", filenames, function(_, index)
    local projectFile = sanitizedFiles[index].filepath
    local isWorkspace = util.hasSuffix(projectFile, "xcworkspace")

    projectConfig.settings().projectFile = projectFile
    projectConfig.settings().projectCommand = (isWorkspace and "-workspace '" or "-project '")
      .. projectFile
      .. "'"
    projectConfig.save_settings()

    if callback then
      callback(projectFile)
    end
  end, opts)
end

function M.select_scheme(schemes, callback, opts)
  if not schemes or not next(schemes) then
    start_telescope_spinner()
  end

  M.show("Select Scheme", schemes, function(value, _)
    projectConfig.settings().scheme = value
    projectConfig.save_settings()

    if callback then
      callback()
    end
  end, opts)

  if not schemes or not next(schemes) then
    local projectCommand = projectConfig.settings().projectCommand
    return xcode.get_project_information(projectCommand, function(info)
      update_results(info.schemes)
    end)
  end
end

function M.select_config(callback, opts)
  local projectCommand = projectConfig.settings().projectCommand
  local projectInfo = nil

  start_telescope_spinner()
  M.show("Select Build Configuration", {}, function(value, _)
    projectConfig.settings().config = value
    projectConfig.save_settings()

    if callback then
      callback(projectInfo)
    end
  end, opts)

  return xcode.get_project_information(projectCommand, function(info)
    projectInfo = info
    update_results(info.configs)
  end)
end

function M.select_testplan(callback, opts)
  local projectCommand = projectConfig.settings().projectCommand
  local scheme = projectConfig.settings().scheme

  start_telescope_spinner()
  M.show("Select Test Plan", {}, function(value, _)
    projectConfig.settings().testPlan = value
    projectConfig.save_settings()

    if callback then
      callback(value)
    end
  end, opts)

  return xcode.get_testplans(projectCommand, scheme, function(testPlans)
    if not testPlans or not next(testPlans) then
      require("xcodebuild.logs").notify("Could not detect test plans", vim.log.levels.WARN)

      if active_picker then
        telescopeActions.close(active_picker.prompt_bufnr)
      end
      if callback then
        callback()
      end
    else
      update_results(testPlans)
    end
  end)
end

function M.select_destination(callback, opts)
  local projectCommand = projectConfig.settings().projectCommand
  local scheme = projectConfig.settings().scheme
  local results = {}

  start_telescope_spinner()
  M.show("Select Device", {}, function(_, index)
    if index <= 0 then
      return
    end

    projectConfig.settings().destination = results[index].id
    projectConfig.settings().platform = results[index].platform
    projectConfig.save_settings()

    if callback then
      callback(results[index])
    end
  end, opts)

  return xcode.get_destinations(projectCommand, scheme, function(destinations)
    local filtered = util.filter(destinations, function(table)
      return table.id ~= nil
        and table.platform ~= "iOS"
        and (not table.name or not string.find(table.name, "^Any"))
    end)

    local destinationsName = util.select(filtered, function(table)
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
    update_results(destinationsName)
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
    "Show Logs",
    "Close Logs",

    "Show Current Configuration",
    "Show Configuration Wizard",
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
    actions.show_logs,
    actions.close_logs,

    actions.show_current_config,
    actions.configure_project,
    actions.uninstall,
  }

  if not projectConfig.is_project_configured() then
    actionsNames = { "Show Configuration Wizard " }
    actionsPointers = { actions.configure_project }
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
