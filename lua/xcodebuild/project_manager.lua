local appdata = require("xcodebuild.appdata")
local projectConfig = require("xcodebuild.project_config")
local util = require("xcodebuild.util")
local pickers = require("xcodebuild.pickers")
local notifications = require("xcodebuild.notifications")
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

  local output = util.shell(helper .. " " .. action .. allParams)
  if output[#output] == "" then
    table.remove(output, #output)
  end

  return output
end

local function select_targets(callback)
  local targets = run("list_targets")
  pickers.show("Select Target(s)", targets, callback, { close_on_select = true, multiselect = true })
end

local function add_file_to_targets(filepath, targets)
  local targetsJoined = table.concat(targets, ",")
  run("add_file", { targetsJoined, filepath })
end

local function update_file_targets(filepath, targets)
  local targetsJoined = table.concat(targets, ",")
  run("update_file_targets", { targetsJoined, filepath })
end

local function delete_file(filepath)
  run("delete_file", { filepath })
  vim.fn.delete(filepath)
end

local function rename_file(oldPath, newPath)
  run("rename_file", { oldPath, newPath })
  vim.fn.rename(oldPath, newPath)
end

local function add_group(path)
  run("add_group", { path })
end

local function rename_group(oldPath, newPath)
  run("rename_group", { oldPath, newPath })
  vim.fn.rename(oldPath, newPath)
end

local function delete_group(path)
  run("delete_group", { path })
  vim.fn.system("rm -rf '" .. path .. "'")
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
  local extension = filename:match("%.(%w+)$") or ""

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

function M.add_current_file()
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  M.add_current_group()

  local filepath = vim.fn.expand("%:p")

  select_targets(function(targets)
    add_file_to_targets(filepath, targets)
    notifications.send("File has been added to targets")
  end)
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
  rename_file(oldFilePath, newFilePath)
  replace_file(newFilePath)
  notifications.send("File has been renamed")
end

function M.delete_current_file()
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  local filepath = vim.fn.expand("%:p")
  local input = vim.fn.input("Delete " .. filepath .. "? (y/n) ", "")
  vim.cmd("echom ''")

  if input == "y" then
    delete_file(filepath)
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

  add_group(groupPath)
  notifications.send("Group has been added")
end

function M.add_current_group()
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  local path = vim.fn.expand("%:p:h")
  add_group(path)
  notifications.send("Group has been added")
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
  rename_group(oldGroupPath, newGroupPath)

  local newFilepath = newGroupPath .. "/" .. vim.fn.expand("%:t")
  replace_file(newFilepath)

  notifications.send("Group has been renamed")
end

function M.delete_current_group()
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  local groupPath = vim.fn.expand("%:p:h")
  local input = vim.fn.input("Delete " .. groupPath .. " with all files? (y/n) ", "")
  vim.cmd("echom ''")

  if input == "y" then
    delete_group(groupPath)
    vim.cmd("bd!")
    notifications.send("Group has been deleted")
  end
end

function M.update_current_file_targets()
  if not helpers.validate_project() or not validate_xcodeproj_tool() then
    return
  end

  local filepath = vim.fn.expand("%:p")

  select_targets(function(targets)
    update_file_targets(filepath, targets)
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
