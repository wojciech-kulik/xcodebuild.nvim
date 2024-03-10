---@mod xcodebuild.health Health Check
---@brief [[
--- This module checks if everything is installed and configured correctly.
---@brief ]]

local health = vim.health or require("health")
local start = health.start or health.report_start
local ok = health.ok or health.report_ok
local warn = health.warn or health.report_warn
local error = health.error or health.report_error

local optional_dependencies = {
  {
    binary = "pymobiledevice3",
    url = "https://github.com/doronz88/pymobiledevice3",
    message = "Required for debugging on physical devices and/or running apps on devices below iOS 17.",
  },
  {
    binary = "xcodeproj",
    url = "https://github.com/CocoaPods/Xcodeproj",
    message = "Required if you want your xcodeproj to be updated when you add, rename, or delete files.",
  },
  {
    binary = "xcbeautify",
    url = "https://github.com/cpisciotta/xcbeautify",
    message = "Required to nicely format Xcode logs.",
  },
}

local required_dependencies = {
  -- {
  --   binary = "codelldb",
  --   url = "https://github.com/vadimcn/codelldb",
  --   message = "Required to debug iOS and macOS apps.",
  -- },
  {
    binary = "xcodebuild",
    url = "https://developer.apple.com/xcode/",
    message = "Required to build, run, and test apps on simulators and physical devices.",
  },
  {
    binary = "xcrun",
    url = "https://developer.apple.com/xcode/",
    message = "Required to interact with simulators and physical devices.",
  },
  {
    binary = "xcode-build-server",
    url = "https://github.com/cpisciotta/xcbeautify",
    message = "Required to ensure that sourcekit-lsp works correctly with Xcode project.",
  },
}

local required_plugins = {
  {
    name = "telescope.nvim",
    lib = "telescope",
    optional = false,
    info = "(Required to present pickers for actions and configurations)",
  },
  {
    name = "nui.nvim",
    lib = "nui.popup",
    optional = false,
    info = "(Required to present floating code coverage report)",
  },
  {
    name = "nvim-tree",
    lib = "nvim-tree",
    optional = true,
    info = "(Required to visually manage project files)",
  },
  {
    name = "nvim-dap",
    lib = "dap",
    optional = true,
    info = "(Required to debug applications)",
  },
  {
    name = "nvim-dap-ui",
    lib = "dapui",
    optional = true,
    info = "(Required to present debugger UI)",
  },
}

---@param binary string
local function check_binary_installed(binary)
  return vim.fn.executable(binary) ~= 0
end

---@param lib_name string
local function plugin_installed(lib_name)
  local res, _ = pcall(require, lib_name)
  return res
end

---@param tools table
---@param optional boolean
local function check_tools(tools, optional)
  for _, tool in ipairs(tools) do
    local installed = check_binary_installed(tool.binary)
    if not installed then
      local err_msg = ("%s: not installed."):format(tool.binary)
      local foo = optional and warn or error
      foo(("%s %s (%s)"):format(err_msg, tool.message, tool.url))
    else
      ok(("%s: installed"):format(tool.binary))
    end
  end
end

local function check_debugger()
  local success, dap = pcall(require, "dap")
  if not success then
    error("codelldb: cannot be checked because dap is not installed.")
    return
  end

  if not dap.adapters.codelldb then
    error("nvim-dap: codelldb adapter not configured.")
    return
  else
    ok("nvim-dap: codelldb adapter configured.")
  end

  if not dap.configurations.swift then
    error("nvim-dap: swift configuration not found.")
    return
  else
    ok("nvim-dap: swift configuration found.")
  end

  local path = dap.adapters.codelldb.executable.command

  if check_binary_installed(path) then
    ok("codelldb: installed")
  else
    error(
      "codelldb: not installed. Required to debug iOS and macOS apps. (https://github.com/vadimcn/codelldb)"
    )
  end
end

local function check_plugins()
  for _, plugin in ipairs(required_plugins) do
    if plugin_installed(plugin.lib) then
      ok(plugin.name .. " installed.")
    else
      local lib_not_installed = plugin.name .. " not installed."
      if plugin.optional then
        warn(("%s %s"):format(lib_not_installed, plugin.info))
      else
        error(lib_not_installed)
      end
    end
  end
end

local function check_build_server()
  local util = require("xcodebuild.util")
  if util.file_exists("buildServer.json") then
    ok("buildServer.json: found")
  else
    warn("file not found. It is required to ensure that sourcekit-lsp works correctly with Xcode project.")
    warn("checked path: " .. vim.fn.getcwd() .. "/buildServer.json")
    warn("did you run checkhealth from the root of your project?")
    warn("run `xcode-build-server config -project XYZ.xcodeproj -scheme XYZ` to create it.")
  end
end

local function check_xcodebuild_settings()
  local util = require("xcodebuild.util")
  if util.dir_exists(".nvim/xcodebuild") then
    ok(".nvim/xcodebuild: found")

    if util.file_exists(".nvim/xcodebuild/settings.json") then
      ok(".nvim/xcodebuild/settings.json: found")
    else
      warn("file not found. It keeps project settings.")
      warn("checked path: " .. vim.fn.getcwd() .. "/.nvim/xcodebuild/settings.json")
      warn("did you run checkhealth from the root of your project?")
      warn("run `:XcodebuildSetup` to configure the project.")
    end
  else
    warn("directory not found")
    warn("checked path: " .. vim.fn.getcwd() .. "/.nvim/xcodebuild")
    warn("did you run checkhealth from the root of your project?")
    warn("run `:XcodebuildSetup` to configure the project.")
  end
end

local function check_xcodebuild_version()
  local util = require("xcodebuild.util")
  local response = util.shell("xcodebuild -version 2>/dev/null")
  local majorVersion, minorVersion = response[1]:match("Xcode (%d+)%.(%d+)")

  if majorVersion then
    if tonumber(majorVersion) < 15 then
      warn(
        "xcodebuild: version "
          .. majorVersion
          .. "."
          .. minorVersion
          .. " was not tested. Use version 15 or higher."
      )
    else
      ok("xcodebuild: version " .. majorVersion .. "." .. minorVersion)
    end
  else
    error("xcodebuild: could not determine version.")
  end
end

local function check_ruby_version()
  local util = require("xcodebuild.util")
  local response = util.shell("ruby --version 2>/dev/null")
  local major, minor, patch = response[1]:match("(%d+)%.(%d+)%.(%d+)")

  if major and minor then
    if tonumber(major .. minor) < 27 then
      error(
        "ruby: version "
          .. major
          .. "."
          .. minor
          .. "."
          .. patch
          .. " is not supported. Use version 2.7 or higher. Required by `xcodeproj`."
      )
    elseif tonumber(major .. minor) < 30 then
      warn(
        "ruby: "
          .. major
          .. "."
          .. minor
          .. "."
          .. patch
          .. " - you are using an old version. Please consider update. Required by `xcodeproj`."
      )
    else
      ok("ruby: version " .. major .. "." .. minor .. "." .. patch)
    end
  else
    error("ruby: could not determine version.")
  end
end

local function check_os()
  local os = vim.loop.os_uname()
  local name = os.sysname
  if name == "Darwin" then
    if os.release:match("^2[3-4]%.") then
      ok("macOS 14+: release " .. os.release)
    else
      warn("macOS below 14 was not tested.")
    end
  else
    error("OS: " .. name .. " is not supported.")
  end
end

local function check_sudo()
  local deviceProxy = require("xcodebuild.platform.device_proxy")
  if not deviceProxy.is_installed() then
    return
  end

  start("Checking passwordless sudo")

  local config = require("xcodebuild.core.config")
  local appdata = require("xcodebuild.project.appdata")
  local util = require("xcodebuild.util")

  local path = config.options.commands.remote_debugger or appdata.tool_path(appdata.REMOTE_DEBUGGER_TOOL)
  local permissions = util.shell("sudo -l 2>/dev/null")

  for _, line in ipairs(permissions) do
    if line:match("NOPASSWD.*" .. path) then
      ok("sudo: configured")
      return
    end
  end

  warn("sudo: passwordless permission for `remote_debugger` is not configured.")
  warn("debugging on physical devices with iOS 17+ will not work.")
  warn("see `:h xcodebuild.sudo` for more information.")
end

local function check_plugin_commit()
  local util = require("xcodebuild.util")
  local pathComponents = vim.split(debug.getinfo(1).source:sub(2), "/", { plain = true })
  local pluginDir = table.concat(pathComponents, "/", 1, #pathComponents - 3)
  local commit = util.shell("git --git-dir '" .. pluginDir .. "/.git' rev-parse --short HEAD 2>/dev/null")[1]
  local upstreamCommit =
    util.shell("git --git-dir '" .. pluginDir .. "/.git' rev-parse --short @{u} 2>/dev/null")[1]

  if commit then
    if upstreamCommit and commit ~= upstreamCommit then
      warn("xcodebuild.nvim: commit #" .. commit .. " is outdated. Please update plugin.")
    else
      ok("xcodebuild.nvim: commit #" .. commit)
    end
  else
    warn("xcodebuild.nvim: commit not found.")
  end
end

local M = {}

M.check = function()
  start("Checking xcodebuild.nvim")
  check_plugin_commit()

  start("Checking OS")
  check_os()

  start("Checking required plugins")
  check_plugins()

  start("Checking required dependencies")
  check_xcodebuild_version()
  check_tools(required_dependencies, false)

  start("Checking optional dependencies")
  check_tools(optional_dependencies, true)
  if check_binary_installed("xcodeproj") then
    check_ruby_version()
  end

  start("Checking debugger")
  check_debugger()

  start("Checking buildServer.json")
  check_build_server()

  start("Checking .nvim/xcodebuild/settings.json")
  check_xcodebuild_settings()

  check_sudo()
end

return M
