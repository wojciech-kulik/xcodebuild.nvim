local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local xcode = require("xcodebuild.xcode")
local config = require("xcodebuild.config")
local util = require("xcodebuild.util")

local M = {}

local show_picker = function(title, items, callback)
	pickers
		.new(require("telescope.themes").get_dropdown({}), {
			prompt_title = title,
			finder = finders.new_table({
				results = items,
			}),
			sorter = conf.generic_sorter(),
			attach_mappings = function(prompt_bufnr, _)
				actions.select_default:replace(function()
					actions.close(prompt_bufnr)

					if callback then
						local selection = action_state.get_selected_entry()
						callback(selection[1], selection.index)
					end
				end)
				return true
			end,
		})
		:find()
end

function M.show(title, items, callback)
	show_picker(title, items, callback)
end

function M.select_device(callback)
	local runtimes = xcode.get_runtimes()
	local runtimesName = util.select(runtimes, function(table)
		return table.name
	end)

	M.show("Select Platform", runtimesName, function(_, runtimeIndex)
		local runtimeId = runtimes[runtimeIndex].id
		local devices = xcode.get_devices(runtimeId)
		local devicesName = util.select(devices, function(table)
			return table.name
		end)

		M.show("Select Device", devicesName, function(_, deviceIndex)
			local deviceId = devices[deviceIndex].id
			config.settings().deviceId = deviceId
			config.save_settings()

			if callback then
				callback()
			end
		end)
	end)
end

function M.select_project(callback)
	local files = vim.split(
		util.shell(
			"find '"
				.. vim.fn.getcwd()
				.. "' \\( -iname '*.xcodeproj' -o -iname '*.xcworkspace' \\) -not -path '*/.*' -not -path '*xcodeproj/project.xcworkspace'"
		),
		"\n",
		{ plain = true }
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

		config.settings().projectFile = projectFile
		config.settings().projectCommand = (isWorkspace and "-workspace '" or "-project '") .. projectFile .. "'"
		config.save_settings()

		if callback then
			callback()
		end
	end)
end

function M.select_scheme(callback)
	local projectCommand = config.settings().projectCommand
	local schemes = xcode.get_schemes(projectCommand)

	M.show("Select Scheme", schemes, function(value, _)
		config.settings().scheme = value
		config.save_settings()

		if callback then
			callback()
		end
	end)
end

function M.select_testplan(callback)
	local projectCommand = config.settings().projectCommand
	local scheme = config.settings().scheme
	local testPlans = xcode.get_testplans(projectCommand, scheme)

	M.show("Select Test Plan", testPlans, function(value, _)
		config.settings().testPlan = value
		config.save_settings()

		if callback then
			callback()
		end
	end)
end

return M
