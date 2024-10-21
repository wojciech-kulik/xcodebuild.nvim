---@mod xcodebuild.integrations.xcodebuild-offline Xcodebuild Workaround
---@tag xcodebuild.xcodebuild-offline
---@brief [[
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
---You can apply this workaround in two ways:
---   1. Manual - by either editing manually `/etc/hosts` and adding
---      `127.0.0.1 developerservices2.apple.com` or by blocking the
---      `developerservices2.apple.com` domain in any network sniffer like
---      Proxyman or Charles Proxy.
---   2. Automatic - more advanced integration that is supported by the plugin.
---      The advantage of this approach is that the Apple server will be blocked
---      only when the `xcodebuild` command (triggered from Neovim) is running.
---      However, it requires a passwordless `sudo` permission for the script.
---
---⚠️ CAUTION
---Giving passwordless `sudo` access to that file, potentially opens a gate for
---malicious software that could modify the file and run some evil code using
---`root` account. The best way to protect that file is to create a local copy,
---change the owner to `root`, and give write permission only to `root`.
---The same must be applied to the parent directory. The script below does
---everything automatically.
---
---👉 Enable integration that automatically blocks Apple servers
---
---Update your config with:
--->lua
---    integrations = {
---      xcodebuild_offline = {
---        enabled = true,
---      },
---    }
---<
---
---👉 Run the following command to install & protect the script
---
--->bash
---    DIR="$HOME/Library/xcodebuild.nvim" && \
---    FILE="$DIR/xcodebuild_offline" && \
---    SOURCE="$HOME/.local/share/nvim/lazy/xcodebuild.nvim/tools/xcodebuild_offline" && \
---    ME="$(whoami)" && \
---    mkdir -p "$DIR" && \
---    cp "$SOURCE" "$FILE" && \
---    chmod 755 "$FILE" && \
---    sudo chown root "$FILE" && \
---    chmod 755 "$DIR" && \
---    sudo chown root "$DIR" && \
---    sudo bash -c "echo \"$ME ALL = (ALL) NOPASSWD: $FILE\" >> /etc/sudoers"
---<
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
  local permissions = util.shell("sudo -l 2>/dev/null")

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
---@param command string
---@return string
function M.wrap_command_if_needed(command)
  if not M.is_enabled() then
    return command
  end

  if not check_sudo() then
    notifications.stop_build_timer()
    error("xcodebuild.nvim: `xcodebuild_offline` requires passwordless access to the sudo command.")
  end

  return "sudo '" .. M.scriptPath .. "' " .. string.gsub(command, "^xcodebuild ", "", 1)
end

return M
