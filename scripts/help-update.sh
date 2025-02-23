#!/bin/bash

lemmy-help \
  --layout compact:0 \
  --indent 2 \
  -f -t -a -c \
  ./lua/xcodebuild/init.lua \
  ./lua/xcodebuild/docs/features.lua \
  ./lua/xcodebuild/docs/requirements.lua \
  ./lua/xcodebuild/docs/highlights.lua \
  ./lua/xcodebuild/docs/keybindings.lua \
  ./lua/xcodebuild/docs/commands.lua \
  ./lua/xcodebuild/docs/global_variables.lua \
  ./lua/xcodebuild/docs/ios17.lua \
  ./lua/xcodebuild/health.lua \
  ./lua/xcodebuild/actions.lua \
  ./lua/xcodebuild/core/constants.lua \
  ./lua/xcodebuild/core/autocmd.lua \
  ./lua/xcodebuild/core/config.lua \
  ./lua/xcodebuild/core/quickfix.lua \
  ./lua/xcodebuild/core/xcode.lua \
  ./lua/xcodebuild/core/previews.lua \
  ./lua/xcodebuild/xcode_logs/parser.lua \
  ./lua/xcodebuild/xcode_logs/panel.lua \
  ./lua/xcodebuild/project/config.lua \
  ./lua/xcodebuild/project/appdata.lua \
  ./lua/xcodebuild/project/builder.lua \
  ./lua/xcodebuild/project/manager.lua \
  ./lua/xcodebuild/project/assets.lua \
  ./lua/xcodebuild/platform/device.lua \
  ./lua/xcodebuild/platform/device_proxy.lua \
  ./lua/xcodebuild/platform/macos.lua \
  ./lua/xcodebuild/broadcasting/events.lua \
  ./lua/xcodebuild/broadcasting/notifications.lua \
  ./lua/xcodebuild/tests/diagnostics.lua \
  ./lua/xcodebuild/tests/enumeration_parser.lua \
  ./lua/xcodebuild/tests/explorer.lua \
  ./lua/xcodebuild/tests/provider.lua \
  ./lua/xcodebuild/tests/runner.lua \
  ./lua/xcodebuild/tests/search.lua \
  ./lua/xcodebuild/tests/snapshots.lua \
  ./lua/xcodebuild/tests/xcresult_parser.lua \
  ./lua/xcodebuild/code_coverage/coverage.lua \
  ./lua/xcodebuild/code_coverage/report.lua \
  ./lua/xcodebuild/integrations/dap.lua \
  ./lua/xcodebuild/integrations/dap-symbolicate.lua \
  ./lua/xcodebuild/integrations/remote_debugger.lua \
  ./lua/xcodebuild/integrations/lsp.lua \
  ./lua/xcodebuild/integrations/nvim-tree.lua \
  ./lua/xcodebuild/integrations/neo-tree.lua \
  ./lua/xcodebuild/integrations/oil-nvim.lua \
  ./lua/xcodebuild/integrations/quick.lua \
  ./lua/xcodebuild/integrations/xcode-build-server.lua \
  ./lua/xcodebuild/integrations/xcodebuild-offline.lua \
  ./lua/xcodebuild/ui/pickers.lua \
  ./lua/xcodebuild/ui/picker_actions.lua \
  ./lua/xcodebuild/helpers.lua \
  ./lua/xcodebuild/util.lua \
  >doc/xcodebuild.txt
