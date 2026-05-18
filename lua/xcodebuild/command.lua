
local M = {}

local function get_builtin_commands()
  local actions = require("xcodebuild.actions")
  return {
    -- Build
    Build = { f = actions.build },
    CleanBuild = { f = actions.clean_build },
    BuildRun = { f = actions.build_and_run },
    BuildForTesting = { f = actions.build_for_testing },
    Run = { f = actions.run },
    Cancel = { f = actions.cancel },

    -- Previews
    PreviewShow = { f = actions.previews_show },
    PreviewHide = { f = actions.previews_hide },
    PreviewToggle = { f = actions.previews_toggle },
    PreviewGenerate = {
      f = function(value)
        actions.previews_generate(value == "hotReload")
      end,
      additional_args = { "hotReload" }
    },
    PreviewGenerateAndShow = {
      f = function(value)
        actions.previews_generate_and_show(value == "hotReload")
      end,
      additional_args = { "hotReload" }
    },

    -- Testing
    Test = { f = actions.run_tests },
    TestTarget = { f = actions.run_target_tests },
    TestClass = { f = actions.run_class_tests },
    TestNearest = { f = actions.run_nearest_test },
    TestSelected = { f = actions.run_selected_tests },
    TestFailing = { f = actions.rerun_failed_tests },
    TestRepeat = { f = actions.repeat_last_test_run },
    FailingSnapshots = { f = actions.show_failing_snapshot_tests },

    -- Coverage
    ToggleCodeCoverage = { f = actions.toggle_code_coverage },
    ShowCodeCoverageReport = { f = actions.show_code_coverage_report },
    JumpToNextCoverage = { f = actions.jump_to_next_coverage },
    JumpToPrevCoverage = { f = actions.jump_to_previous_coverage },

    -- Test Explorer
    TestExplorerShow = { f = actions.test_explorer_show },
    TestExplorerHide = { f = actions.test_explorer_hide },
    TestExplorerToggle = { f = actions.test_explorer_toggle },
    TestExplorerClear = { f = actions.test_explorer_clear },
    TestExplorerRunSelectedTests = { f = actions.test_explorer_run_selected_tests },
    TestExplorerRerunTests = { f = actions.test_explorer_rerun_tests },

    -- Pickers
    Setup = { f = actions.configure_project },
    Picker = { f = actions.show_picker },
    SelectScheme = { f = actions.select_scheme },
    SelectDevice = { f = actions.select_device },
    SelectTestPlan = { f = actions.select_testplan },
    NextDevice = { f = actions.select_next_device },
    PreviousDevice = { f = actions.select_previous_device },

    -- Logs
    ToggleLogs = { f = actions.toggle_logs },
    OpenLogs = { f = actions.open_logs },
    CloseLogs = { f = actions.close_logs },

    -- Project Manager
    ProjectManager = { f = actions.show_project_manager_actions },
    CreateNewFile = { f = actions.create_new_file },
    AddCurrentFile = { f = actions.add_current_file },
    DeleteCurrentFile = { f = actions.delete_current_file },
    RenameCurrentFile = { f = actions.rename_current_file },
    CreateNewGroup = { f = actions.create_new_group },
    AddCurrentGroup = { f = actions.add_current_group },
    RenameCurrentGroup = { f = actions.rename_current_group },
    DeleteCurrentGroup = { f = actions.delete_current_group },
    UpdateCurrentFileTargets = { f = actions.update_current_file_targets },
    ShowCurrentFileTargets = { f = actions.show_current_file_targets },

    -- Assets Manager
    AssetsManager = { f = actions.show_assets_manager },

    -- Other
    EditEnvVars = { f = actions.edit_env_vars },
    EditRunArgs = { f = actions.edit_run_args },
    ShowConfig = { f = actions.show_current_config },
    BootSimulator = { f = actions.boot_simulator },
    CleanDerivedData = { f = actions.clean_derived_data },
    InstallApp = { f = actions.install_app },
    UninstallApp = { f = actions.uninstall_app },
    OpenInXcode = { f = actions.open_in_xcode },
    QuickfixLine = { f = actions.quickfix_line },
    CodeActions = { f = actions.show_code_actions },

    -- Swift Macros
    ApproveMacros = { f = actions.approve_macros },

    -- Backward compatibility
    TestFunc = {
      f = function()
        print("xcodebuild.nvim: Use `XcodebuildTestNearest` instead of `XcodebuildTestFunc`")
      end,
    },
  }
end

local function get_dap_commands()
  local dap = require("xcodebuild.integrations.dap")
  return {
    AttachDebugger = { f = attach_and_debug },
    DetachDebugger = { f = detach_debugger },
    BuildDebug = { f = build_and_debug },
    Debug = { f = debug_without_build },
  }
end

local function load_command(maps, cmd, ...)
  if cmd == nil then
    vim.notify("Select a valid Xcodebuild command", vim.log.levels.ERROR)
    return
  end

  local command = maps[cmd]
  if command == nil then
    vim.notify("Invalid Xcodebuild command '" .. cmd .."'", vim.log.levels.ERROR)
    return
  end

  local args = {...}

  command.f(unpack(args))
end

function M.register_user_command(opts)
  local opts = opts or {}

  local include_dap_commands = opts["include_dap"] or false

  local cmds = get_builtin_commands()
  if include_dap_commands then
    local dap_cmds = get_dap_commands()
    for k, v in pairs(dap_cmds) do
      cmds[k] = v
    end
  end

  vim.api.nvim_create_user_command("Xcodebuild", function(opts)
    load_command(cmds, unpack(opts.fargs))
  end,
    {
      nargs = "*",
      complete = function(_, line)
        local keyset = {}
        for k,v in pairs(cmds) do
          keyset[#keyset + 1] = k
        end
        table.sort(keyset)

        local l = vim.split(line, "%s+")
        local n = #l - 2

        if n == 0 then
          local current = l[2]:lower()
          return vim.tbl_filter(function(val)
            return string.find(val:lower(), current)
          end, keyset)
        end

        if n == 1 then
          local args = cmds[l[2]]["additional_args"] or {}
          local current = l[3]:lower()
          return vim.tbl_filter(function(val)
            return string.find(val:lower(), current)
          end, args)
        end

        return {}
      end,
    }
  )
end

return M
