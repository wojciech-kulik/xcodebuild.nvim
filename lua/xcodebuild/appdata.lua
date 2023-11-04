local util = require("xcodebuild.util")

local M = {}

local appdir = vim.fn.getcwd() .. "/.nvim/xcodebuild"
local original_logs_filename = "original_logs.log"
local build_logs_filename = "xcodebuild.log"

local function write_to_app_dir(data, filename)
	M.create_app_dir()
	vim.fn.writefile(data, appdir .. "/" .. filename)
end

local function read_from_app_dir(filename)
	return vim.fn.readfile(appdir .. "/" .. filename)
end

local function remove_from_app_dir(filename)
	util.shell("rm -f " .. appdir .. "/" .. filename)
end

function M.get_original_logs_filepath()
	return appdir .. "/" .. original_logs_filename
end

function M.get_build_logs_filename()
	return build_logs_filename
end

function M.get_build_logs_filepath()
	return appdir .. "/" .. build_logs_filename
end

function M.create_app_dir()
	util.shell("mkdir -p .nvim/xcodebuild")
end

function M.delete_original_logs()
	remove_from_app_dir(original_logs_filename)
end

function M.read_original_logs()
	return read_from_app_dir(original_logs_filename)
end

function M.write_original_logs(data)
	write_to_app_dir(data, original_logs_filename)
end

function M.read_build_logs()
	return read_from_app_dir(build_logs_filename)
end

function M.write_build_logs(data)
	write_to_app_dir(data, build_logs_filename)
end

return M
