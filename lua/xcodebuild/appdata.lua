local util = require("xcodebuild.util")

local M = {}

M.appdir = vim.fn.getcwd() .. "/.nvim/xcodebuild"
M.original_logs_filename = "original_logs.log"
M.original_logs_filepath = M.appdir .. "/" .. M.original_logs_filename
M.build_logs_filename = "xcodebuild.log"
M.build_logs_filepath = M.appdir .. "/" .. M.build_logs_filename
M.snapshots_dir = M.appdir .. "/failing-snapshots"

GETSNAPSHOTS_TOOL = "getsnapshots"

function M.tool_path(name)
  local pathComponents = vim.split(debug.getinfo(1).source:sub(2), "/", { plain = true })
  return table.concat(pathComponents, "/", 1, #pathComponents - 3) .. "/tools/" .. name
end

function M.create_app_dir()
  util.shell("mkdir -p .nvim/xcodebuild")
end

function M.read_original_logs()
  return vim.fn.readfile(M.original_logs_filepath)
end

function M.write_original_logs(data)
  vim.fn.writefile(data, M.original_logs_filepath)
end

function M.read_build_logs()
  return vim.fn.readfile(M.build_logs_filepath)
end

function M.write_build_logs(data)
  vim.fn.writefile(data, M.build_logs_filepath)
end

return M
