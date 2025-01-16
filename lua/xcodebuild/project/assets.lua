---@mod xcodebuild.project.assets Project Assets Manager
---@brief [[
---This module contains the functionality to manage Xcode project assets.
---
---It allows to add, delete, and browse assets in the project.
---Supported asset types are: images, colors, and data.
---@brief ]]

local pickers = require("xcodebuild.ui.pickers")
local util = require("xcodebuild.util")
local notifications = require("xcodebuild.broadcasting.notifications")

local M = {}

---Validates if `fd` is installed.
---If not, it shows an error notification.
---@return boolean
local function validate_if_fd_installed()
  if not util.is_fd_installed() then
    notifications.send_error("`fd` is required by Assets Manager. To install run: brew install fd")
    return false
  end

  return true
end

---Removes trailing slashes from a list of paths and removes empty strings.
---@param paths string[]
---@return string[]
local function clean_up_paths(paths)
  local result = {}

  for _, dir in ipairs(paths) do
    if dir ~= "" then
      local trimmed = dir:gsub("/+$", "")
      table.insert(result, trimmed)
    end
  end

  return result
end

---Shows a picker to select an asset.
---@param callback function(string)|nil
local function select_assets(callback)
  local assets = util.shell({
    "fd",
    "--type",
    "d",
    ".*\\.xcassets$",
  })
  assets = clean_up_paths(assets)

  pickers.show("Select Assets", assets, function(asset, _)
    util.call(callback, asset.value)
  end)
end

---Shows a picker to select a folder.
---@param assetsDir string
---@param deleteMode boolean
---@param callback function(string)|nil
local function select_folder(assetsDir, deleteMode, callback)
  local folders = util.shell({
    "fd",
    "--type",
    "d",
    "-E",
    "*.colorset",
    "-E",
    "*.imageset",
    "-E",
    "*.dataset",
    "-E",
    "*.appiconset",
    ".",
    assetsDir,
  })

  if not deleteMode then
    table.insert(folders, 1, assetsDir)
    table.insert(folders, 2, "")
    if #folders > 2 then
      table.insert(folders, 3, "")
    end
  end
  folders = clean_up_paths(folders)

  local titles = util.select(folders, function(folder)
    local trimmed = folder:gsub(assetsDir .. "/", "")
    return trimmed
  end)

  if not deleteMode then
    titles[1] = "[Root]"
    titles[2] = "[Create New Folder]"
    if #titles > 2 then
      titles[3] = ""
    end
  end

  pickers.show("Select Folder", titles, function(_, index)
    if deleteMode then
      util.call(callback, folders[index])
      return
    end

    if index == 2 then
      pickers.close()

      local newFolder = vim.fn.input("Enter folder name: ")
      if newFolder == "" then
        notifications.send_error("Invalid folder name")
        return
      end

      local path = vim.fs.joinpath(assetsDir, newFolder)
      util.shell({ "mkdir", "-p", path })
      util.call(callback, path)
    elseif index ~= 3 then
      util.call(callback, folders[index])
    end
  end)
end

---Shows a picker to select the asset type.
---@param callback function(string)|nil
local function select_asset_type(callback)
  local assetTypes = { "Image", "Color", "Data" }

  pickers.show("Select Asset Type", assetTypes, function(assetType, _)
    util.call(callback, assetType.value)
  end, { close_on_select = true })
end

---Creates a new image set.
---@param filename string
---@param path string
---@param template boolean renderings as template
function M.create_image(filename, path, template)
  if not string.find(filename, ".", nil, true) then
    notifications.send_error("Invalid filename. Example: image.png")
    return
  end

  local filenameNoExt = vim.fn.fnamemodify(filename, ":t:r")
  path = vim.fs.joinpath(path, filenameNoExt .. ".imageset")
  util.shell({ "mkdir", "-p", path })

  local json = {
    "{",
    '  "images" : [',
    "    {",
    '      "filename" : "' .. filename .. '",',
    '      "idiom" : "universal"',
    "    }",
    "  ],",
    '  "info" : {',
    '     "author" : "xcode",',
    '     "version" : 1',
  }

  if template then
    table.insert(json, "  },")
    table.insert(json, '  "properties" : {')
    table.insert(json, '    "template-rendering-intent" : "template"')
    table.insert(json, "  }")
  else
    table.insert(json, "  }")
  end

  table.insert(json, "}")

  vim.fn.writefile(json, vim.fs.joinpath(path, "Contents.json"))
  notifications.send("Paste the image named '" .. filename .. "' in the imageset folder")
  util.shell({ "open", "-a", "Finder", path })
end

---Creates a new data set.
---@param filename string
---@param path string
function M.create_data(filename, path)
  if not string.find(filename, ".", nil, true) then
    notifications.send_error("Invalid filename. Example: data.json")
    return
  end

  local filenameNoExt = vim.fn.fnamemodify(filename, ":t:r")
  path = vim.fs.joinpath(path, filenameNoExt .. ".dataset")
  util.shell({ "mkdir", "-p", path })

  local json = {
    "{",
    '  "data" : [',
    "    {",
    '      "filename" : "' .. filename .. '",',
    '      "idiom" : "universal"',
    "    }",
    "  ],",
    '  "info" : {',
    '     "author" : "xcode",',
    '     "version" : 1',
    "  }",
    "}",
  }

  vim.fn.writefile(json, vim.fs.joinpath(path, "Contents.json"))
  notifications.send("Paste the file named '" .. filename .. "' in the dataset folder")
  util.shell({ "open", "-a", "Finder", path })
end

---Creates a new color set.
---@param name string color name
---@param color string color in hex format, e.g. #FF0000
---@param path string
function M.create_color(name, color, path)
  if not name or name == "" then
    notifications.send_error("Invalid color name. Example: DarkBlue")
    return
  end

  if not color:match("^#[0-9A-Fa-f]+$") or (#color ~= 7 and #color ~= 9) then
    notifications.send_error("Invalid color format. Use #RRGGBB or #AARRGGBB")
    return
  end

  path = vim.fs.joinpath(path, name .. ".colorset")
  util.shell({ "mkdir", "-p", path })

  color = color:gsub("#", "")
  local alpha = 1.0
  if #color == 8 then
    alpha = tonumber(color:sub(1, 2), 16) / 255.0
    color = color:sub(3)
  end

  local red = color:sub(1, 2)
  local green = color:sub(3, 4)
  local blue = color:sub(5, 6)

  local json = {
    "{",
    '  "colors" : [',
    "    {",
    '      "color" : {',
    '        "color-space" : "srgb",',
    '        "components" : {',
    '          "alpha" : "' .. (alpha == 1 and "1.0" or tostring(alpha)) .. '",',
    '          "blue" : "0x' .. blue .. '",',
    '          "green" : "0x' .. green .. '",',
    '          "red" : "0x' .. red .. '"',
    "        }",
    "      },",
    '      "idiom" : "universal"',
    "    },",
    "  ],",
    '  "info" : {',
    '     "author" : "xcode",',
    '     "version" : 1',
    "  }",
    "}",
  }

  vim.fn.writefile(json, vim.fs.joinpath(path, "Contents.json"))
  notifications.send("Color '" .. name .. "' has been added")
end

---Shows a picker to delete a folder.
function M.delete_folder_picker()
  if not validate_if_fd_installed() then
    return
  end

  select_assets(function(asset)
    select_folder(asset, true, function(path)
      local confirm = vim.fn.confirm("Are you sure you want to delete: " .. path .. "?", "&Yes\n&No", 2) == 1

      if confirm then
        util.shell({ "rm", "-rf", path })
        pickers.close()
        notifications.send("Folder deleted: " .. path)
      end
    end)
  end)
end

---Shows a wizard to create a new asset.
function M.create_new_asset_picker()
  if not validate_if_fd_installed() then
    return
  end

  select_assets(function(asset)
    select_folder(asset, false, function(path)
      select_asset_type(function(assetType)
        if assetType == "Image" then
          local filename = vim.fn.input("Enter filename (e.g. image.svg): ")
          pickers.show("Do you want to render as template image?", { "Yes", "No" }, function(_, index)
            M.create_image(filename, path, index == 1)
          end, { close_on_select = true })
        elseif assetType == "Data" then
          local filename = vim.fn.input("Enter filename (e.g. file.json): ")
          M.create_data(filename, path)
        elseif assetType == "Color" then
          local name = vim.fn.input("Enter color name (e.g. DarkRed): ")
          local color = vim.fn.input("Enter color (e.g. #FF0000 or #AAFF0000): ")
          M.create_color(name, color, path)
        end
      end)
    end)
  end)
end

---Shows a picker with all the assets in the project.
---Opens the asset in Finder or Quick Look.
---@param reveal boolean reveal in Finder
function M.show_asset_picker(reveal)
  if not validate_if_fd_installed() then
    return
  end

  local assets = util.shell({
    "fd",
    "--type",
    "f",
    "--full-path",
    ".*\\.xcassets/.*",
    "-E",
    "Contents.json",
  })
  assets = clean_up_paths(assets)

  pickers.show("Show Asset", assets, function(asset, _)
    local isImage = string.find(asset.value, "%.imageset") or string.find(asset.value, "%.appiconset")

    if isImage and not reveal then
      vim.fn.jobstart({ "qlmanage", "-p", asset.value }, {
        detach = true,
        on_exit = function() end,
      })

      -- HACK: the preview stays behind the terminal window
      -- when Neovim is running in tmux or zellij.
      if vim.env.TERM_PROGRAM == "tmux" or vim.env.ZELLIJ_PANE_ID then
        vim.defer_fn(function()
          util.shell("open -a qlmanage")
        end, 100)
      end
    else
      local parent = vim.fn.fnamemodify(asset.value, ":h")
      vim.fn.jobstart({ "open", "-a", "Finder", parent }, {
        detach = true,
        on_exit = function() end,
      })
    end
  end, { close_on_select = true })
end

---Shows a picker to delete an asset.
function M.delete_asset_picker()
  if not validate_if_fd_installed() then
    return
  end

  local assets = util.shell({
    "fd",
    "--type",
    "d",
    "--full-path",
    ".*\\.xcassets/.*\\.(imageset|colorset|dataset)",
  })
  assets = clean_up_paths(assets)

  pickers.show("Delete Asset", assets, function(asset, _)
    if not asset or not asset.value or asset.value == "" then
      return
    end

    -- safety check
    if asset.value == "" or asset.value == "/" or asset.value == vim.fn.expand("~") then
      notifications.send_error("Cannot delete root directory")
      return
    end

    local confirm = vim.fn.confirm("Are you sure you want to delete: " .. asset.value .. "?", "&Yes\n&No", 2)
      == 1

    if confirm then
      util.shell({ "rm", "-rf", asset.value })
      pickers.close()
      notifications.send("Asset deleted: " .. asset.value)
    end
  end)
end

---Shows the Assets Manager with all available actions.
function M.show_assets_manager()
  if not validate_if_fd_installed() then
    return
  end

  local titles = {
    "Create New Asset",
    "Delete Asset",
    "Delete Folder",
    "Preview Asset",
    "Reveal Asset in Finder",
  }
  local actions = {
    M.create_new_asset_picker,
    M.delete_asset_picker,
    M.delete_folder_picker,
    function()
      M.show_asset_picker(false)
    end,
    function()
      M.show_asset_picker(true)
    end,
  }

  pickers.show("Assets Manager", titles, function(_, selectedIndex)
    actions[selectedIndex]()
  end)
end

return M
