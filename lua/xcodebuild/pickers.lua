local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")
local xcode = require("xcodebuild.xcode")
local config = require("xcodebuild.config")

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

function M.select_device()
	local runtimes = xcode.get_runtimes()

	local runtimesName = {}
	for _, runtime in ipairs(runtimes) do
		table.insert(runtimesName, runtime.name)
	end

	M.show("Select Platform", runtimesName, function(_, runtimeIndex)
		local runtimeId = runtimes[runtimeIndex].id
		local devices = xcode.get_devices(runtimeId)

		local devicesName = {}
		for _, device in ipairs(devices) do
			table.insert(devicesName, device.name)
		end

		M.show("Select Device", devicesName, function(_, deviceIndex)
			local deviceId = devices[deviceIndex].id
			config.settings().deviceId = deviceId
			config.save_settings()
		end)
	end)
end

return M
