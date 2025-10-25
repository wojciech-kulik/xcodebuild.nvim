---@mod xcodebuild.integrations.xcodebuild-offline Xcodebuild Workaround
---@tag xcodebuild.xcodebuild-offline
---@brief [[
---
---NOTE: This issue has been fixed in Xcode 26 and later versions.
---
---This module provides a workaround for the issue with slow `xcodebuild` command.
---
---The issue is caused by the fact that `xcodebuild` tries to connect to the Apple
---servers before building the project, which can take 20 seconds or more.
---Usually, those requests are not necessary, but they slow down each build.
---
---This module provides a workaround by mapping Apple servers to localhost in the
---`/etc/hosts` file during the build. It is a temporary solution and should be
---used with caution.
---
---Keep in mind that disabling access to `developerservices2.apple.com` for
---`xcodebuild` may cause some issues with the build process. It will disable
---things like registering devices, capabilities, and other network-related
---features. Therefore, it's best to use it when you are working just on the
---code and don't need updating project settings.
---
---Below you can find three ways to enable the workaround.
---
---1. Manual (script)
---
---Enable workaround:
--->bash
---  sudo bash -c "echo '127.0.0.1 developerservices2.apple.com' >>/etc/hosts"
---<
---
---Disable workaround:
--->bash
---  sudo sed -i '' '/developerservices2\.apple\.com/d' /etc/hosts
---<
---
---2. Manual (network sniffer)
---
---If you use some tool to sniff network traffic like Proxyman or Charles Proxy,
---you can block requests to `https://developerservices2.apple.com/*` and
---automatically return some error like 999 status code. It will prevent
---`xcodebuild` from further calls.
---
---3. Automatic (`xcodebuild.nvim` integration)
---
---In this approach the Apple server will be blocked only when the `xcodebuild`
---command (triggered by the plugin) is running. However, it requires a passwordless
---`sudo` permission for the script.
---
---⚠️ CAUTION
---Giving passwordless `sudo` access to that file, potentially opens a gate for
---malicious software that could modify the file and run some evil code using
---`root` account. The best way to protect that file is to create a local copy,
---change the owner to `root`, and give write permission only to `root`. The same
---must be applied to the parent directory. The script below automatically
---secures the file.
---
---👉 Enable integration that automatically blocks Apple servers
---
---Update your config with:
--->lua
---  integrations = {
---    xcodebuild_offline = {
---      enabled = true,
---    },
---  }
---<
---
---👉 Run the following command to install & protect the script
---
--->bash
---  DEST="$HOME/Library/xcodebuild.nvim" && \
---    SOURCE="$HOME/.local/share/nvim/lazy/xcodebuild.nvim/tools/xcodebuild_offline" && \
---    ME="$(whoami)" && \
---    sudo install -d -m 755 -o root "$DEST" && \
---    sudo install -m 755 -o root "$SOURCE" "$DEST" && \
---    sudo bash -c "echo \"$ME ALL = (ALL) NOPASSWD: $DEST/xcodebuild_offline\" >> /etc/sudoers"
---<
---
---
---More details about this issue can be found here:
---https://github.com/wojciech-kulik/xcodebuild.nvim/issues/201#issuecomment-2423828065
---
---@brief ]]

local config = require("xcodebuild.core.config").options.integrations.xcodebuild_offline
local util = require("xcodebuild.util")
local notifications = require("xcodebuild.broadcasting.notifications")

local M = {}

M.scriptPath = vim.fn.expand("~/Library/xcodebuild.nvim/xcodebuild_offline")

---Checks whether the `sudo` command has passwordless access to the tool.
---@return boolean
local function check_sudo()
  local permissions = util.shell("sudo -l")

  for _, line in ipairs(permissions) do
    if line:match("NOPASSWD.*" .. M.scriptPath) then
      return true
    end
  end

  return false
end

---Returns whether the `xcodebuild` command should be run in offline mode.
---@return boolean
function M.is_enabled()
  return config.enabled and util.file_exists(M.scriptPath)
end

---Wraps the `xcodebuild` command with the workaround script if needed.
---@param command string[]
---@return string[]
function M.wrap_command_if_needed(command)
  if not M.is_enabled() then
    return command
  end

  if not check_sudo() then
    notifications.stop_build_timer()
    error("xcodebuild.nvim: `xcodebuild_offline` requires passwordless access to the sudo command.")
  end

  table.insert(command, 1, "sudo")
  command[2] = M.scriptPath

  return command
end

return M
