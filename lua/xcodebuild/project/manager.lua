local appdata = require("xcodebuild.project.appdata")
local projectConfig = require("xcodebuild.project.config")
local util = require("xcodebuild.util")
local pickers = require("xcodebuild.ui.pickers")
local notifications = require("xcodebuild.broadcasting.notifications")
local helpers = require("xcodebuild.helpers")

local M = {}

local helper = "ruby '" .. appdata.tool_path(PROJECT_HELPER_TOOL) .. "'"

local function validate_xcodeproj_tool()
  if vim.fn.executable("xcodeproj") == 0 then
    notifications.send_error("Xcodeproj tool not found. Please run `gem install xcodeproj` to install it.")
    return false
  end

  return true
end

local function run(action, params)
  local allParams = ""
  local project = projectConfig.settings.xcodeproj
  params = params or {}
  table.insert(params, 1, project)

  for _, param in ipairs(params) do
    allParams = allParams .. " '" .. param .. "'"
  end

  local errorFile = "/tmp/xcodebuild_nvimtree"
  local output = util.shell(helper .. " " .. action .. allParams .. " 2> " .. errorFile)

  if output[#output] == "" then
    table.remove(output, #output)
  end

  if output[1] and vim.startswith(output[1], "WARN:") then
    vim.notify(table.concat(output, "\n"):sub(7), vim.log.levels.WARN)
    return {}
  end

  local stderr_file = io.open(errorFile, "r")
  if stderr_file then
    if stderr_file:read("*all") ~= "" then
      vim.notify(
        "Could not update Xcode project file.\n"
          .. "To see more details please check /tmp/xcodebuild_nvimtree.\n"
          .. "If you are trying to add files to SPM packages, you may want to filter them out in the config using: integrations.nvim_tree.should_update_project.\n"
          .. "If the error is unexpected, please open an issue on GitHub.",
        vim.log.levels.ERROR
      )
      return {}
    end
  end

  return output
end

local function run_list_targets()
  return run("list_targets")
end

local function run_select_targets(callback)
  local targets = run_list_targets()
  pickers.show("Select Target(s)", targets, callback, { close_on_select = true, multiselect = true })
end

local function run_add_file_to_targets(filepath, targets)
  local targetsJoined = table.concat(targets, ",")
  run("add_file", { targetsJoined, filepath })
end

local function run_update_file_targets(filepath, targets)
  local targetsJoined = table.concat(targets, ",")
  run("update_file_targets", { targetsJoined, filepath })
end

local function run_delete_file(filepath)
  run("delete_file", { filepath })
end

local function run_rename_file(oldPath, newPath)
  run("rename_file", { oldPath, newPath })
end

local function run_move_file(oldPath, newPath)
  run("move_file", { oldPath, newPath })
end

local function run_add_group(path)
  run("add_group", { path })
end

local function run_rename_group(oldPath, newPath)
  run("rename_group", { oldPath, newPath })
end

local function run_move_group(oldPath, newPath)
  run("move_group", { oldPath, newPath })
end

local function run_delete_group(path)
  run("delete_group", { path })
end

local function replace_file(path)
  vim.cmd("bd! | e " .. path)
end

function M.create_new_file()
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  local path = vim.fn.expand("%:p:h")
  local filename = vim.fn.input("File name: ", "")
  local extension = filename:match("%.([%w_]+)$") or ""

  if vim.trim(filename) == "" then
    return
  end

  if extension == "" then
    filename = filename .. ".swift"
  end

  local fullPath = path .. "/" .. filename
  vim.fn.system("touch '" .. fullPath .. "'")
  vim.cmd("e " .. fullPath)

  M.add_current_file()
end

function M.add_file_to_targets(filepath, targets)
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  run_add_file_to_targets(filepath, targets)
end

---Returns the project targets.
---@return string[]|nil
function M.get_project_targets()
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  return run_list_targets()
end

function M.add_file(filepath)
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  run_select_targets(function(targets)
    local dir = vim.fs.dirname(filepath)
    M.add_group(dir, { silent = true })
    run_add_file_to_targets(filepath, targets)
    notifications.send("File has been added to targets")
  end)
end

function M.add_current_file()
  M.add_file(vim.fn.expand("%:p"))
end

function M.move_file(oldFilePath, newFilePath)
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  run_move_file(oldFilePath, newFilePath)

  if vim.fs.basename(oldFilePath) == vim.fs.basename(newFilePath) then
    notifications.send("File has been moved")
  else
    notifications.send("File has been renamed")
  end
end

function M.rename_file(oldFilePath, newFilePath)
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  run_rename_file(oldFilePath, newFilePath)
  notifications.send("File has been renamed")
end

function M.rename_current_file()
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  local oldFilePath = vim.fn.expand("%:p")
  local filename = vim.fn.expand("%:t")
  local newFilename = vim.fn.input("New file name: ", filename)

  if vim.trim(newFilename) == "" or newFilename == filename then
    return
  end

  local newFilePath = vim.fn.expand("%:p:h") .. "/" .. newFilename
  run_rename_file(oldFilePath, newFilePath)
  vim.fn.rename(oldFilePath, newFilePath)
  replace_file(newFilePath)
  notifications.send("File has been renamed")
end

function M.delete_file(filepath)
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  run_delete_file(filepath)
  notifications.send("File has been deleted")
end

function M.delete_current_file()
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  local filepath = vim.fn.expand("%:p")
  local input = vim.fn.input("Delete " .. filepath .. "? (y/n) ", "")
  vim.cmd("echom ''")

  if input == "y" then
    run_delete_file(filepath)
    vim.fn.delete(filepath)
    vim.cmd("bd!")
    notifications.send("File has been deleted")
  end
end

function M.create_new_group()
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  local path = vim.fn.expand("%:p:h")
  local groupName = vim.fn.input("Group name: ", "")

  if vim.trim(groupName) == "" then
    return
  end

  local groupPath = path .. "/" .. groupName
  vim.fn.system("mkdir -p '" .. groupPath .. "'")

  run_add_group(groupPath)
  notifications.send("Group has been added")
end

function M.add_group(path, opts)
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  opts = opts or {}
  run_add_group(path)

  if not opts.silent then
    notifications.send("Group has been added")
  end
end

function M.add_current_group()
  M.add_group(vim.fn.expand("%:p:h"))
end

function M.rename_group(oldGroupPath, newGroupPath)
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  run_rename_group(oldGroupPath, newGroupPath)
  notifications.send("Group has been renamed")
end

function M.rename_current_group()
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  local oldGroupPath = vim.fn.expand("%:p:h")
  local oldGroupName = vim.fn.expand("%:p:h:t")

  local newGroupName = vim.fn.input("New group name: ", oldGroupName)
  if vim.trim(newGroupName) == "" or oldGroupName == newGroupName then
    return
  end

  local newGroupPath = vim.fn.expand("%:p:h:h") .. "/" .. newGroupName
  run_rename_group(oldGroupPath, newGroupPath)
  vim.fn.rename(oldGroupPath, newGroupPath)

  local newFilepath = newGroupPath .. "/" .. vim.fn.expand("%:t")
  replace_file(newFilepath)

  notifications.send("Group has been renamed")
end

function M.move_or_rename_group(oldGroupPath, newGroupPath)
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  if vim.fs.basename(oldGroupPath) == vim.fs.basename(newGroupPath) then
    run_move_group(oldGroupPath, newGroupPath)
    notifications.send("Group has been moved")
  else
    run_rename_group(oldGroupPath, newGroupPath)
    notifications.send("Group has been renamed")
  end
end

function M.delete_group(groupPath)
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  run_delete_group(groupPath)
  notifications.send("Group has been deleted")
end

function M.delete_current_group()
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  local groupPath = vim.fn.expand("%:p:h")
  local input = vim.fn.input("Delete " .. groupPath .. " with all files? (y/n) ", "")
  vim.cmd("echom ''")

  if input == "y" then
    run_delete_group(groupPath)
    vim.fn.system("rm -rf '" .. groupPath .. "'")
    vim.cmd("bd!")
    notifications.send("Group has been deleted")
  end
end

function M.update_current_file_targets()
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  local filepath = vim.fn.expand("%:p")

  run_select_targets(function(targets)
    run_update_file_targets(filepath, targets)
    notifications.send("File targets have been updated")
  end)
end

function M.show_current_file_targets()
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  local filepath = vim.fn.expand("%:p")
  local filename = vim.fn.expand("%:t")
  local targets = run("list_targets_for_file", { filepath })
  pickers.show("Target Membership of " .. filename, targets)
end

function M.show_action_picker()
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  local titles = {
    "Create new file",
    "Add current file",
    "Rename current file",
    "Delete current file",
    "Create new group",
    "Add current group",
    "Rename current group",
    "Delete current group",
    "Update current file target(s)",
    "Show current file target(s)",
  }

  local actions = {
    M.create_new_file,
    M.add_current_file,
    M.rename_current_file,
    M.delete_current_file,
    M.create_new_group,
    M.add_current_group,
    M.rename_current_group,
    M.delete_current_group,
    M.update_current_file_targets,
    M.show_current_file_targets,
  }

  pickers.show("Project Manager", titles, function(_, index)
    actions[index]()
  end, { close_on_select = true })
end

return M
