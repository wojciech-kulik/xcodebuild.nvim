# Contributing to xcodebuild.nvim

Thank you for your interest in contributing 🍻!  
Below you will find some essential information on how to start.

## Confirming Your Ideas

Before you start working on some features or changes, it would be best to discuss it first either in
[issues](https://github.com/wojciech-kulik/xcodebuild.nvim/issues) or [discussions](https://github.com/wojciech-kulik/xcodebuild.nvim/discussions)
to confirm the approach and to make sure that these changes are desired for this plugin.

Use discussions for general ideas or use issues if it's related to a specific request or ticket.

This way we can both spare our time and avoid unnecessary work 🙏.

## Documentation

The code has been fully documented using LuaLS annotations, which are then used by
[lemmy-help](https://github.com/numToStr/lemmy-help/blob/master/emmylua.md) tool to generate the documentation.

These comments are not only for documentation but also to provide knowledge about data types to the LSP.
This way the project can track if types are correct and if fields should be checked against `nil` value.
LSP also provides this information via auto-completion.

You will find plenty of information about functions both in the code and in the help, so don't be scared to run:

```
:h xcodebuild
```

> [!TIP]
> Remember that you can quickly navigate between tags in the help using `Ctrl+]`.

## Neovim Configuration

To start development on the plugin you should do the following steps:

1. Create a fork of this repository.
2. Clone it locally (keep the default name of the folder - should be `xcodebuild.nvim`).
3. If you are using lazy.nvim, make sure to set up your dev directory to the place where you cloned the repository. Sample config:
   ```lua
   require("lazy").setup(plugins, {
     dev = {
       path = "/Users/me/repositories",
     },
   })
   ```
4. If you prefer, you can create a new config for the development. Just create a new folder in `~/.config` e.g. `nvim-dev` and run:
   ```
   NVIM_APPNAME=nvim-dev nvim
   ```
   It will start Neovim using the new config.
5. The last step is to switch `xcodebuild.nvim` to your local version. With lazy.nvim it's very easy. Just add `dev = true`:
   ```lua
   return {
     "wojciech-kulik/xcodebuild.nvim",
     dependencies = {
       "nvim-telescope/telescope.nvim",
       "MunifTanjim/nui.nvim",
     },
     dev = true,
     config = function()
         -- ...
     end,
   }
   ```

## Tools

The following are used when running CI checks and are strongly recommended during the local development.

Lint: [luacheck](https://github.com/lunarmodules/luacheck/)  
Style: [StyLua](https://github.com/JohnnyMorganz/StyLua)  
LSP: [LuaLS](https://github.com/LuaLS/lua-language-server)  
Docs: [lemmy-help](https://github.com/numToStr/lemmy-help)

You can install them via `homebrew`.  
You can also run `make install-dev` to install them all together including dependencies required by the plugin itself.

## Quality Assurance

The following quality checks are mandatory and are performed during CI.

You can run them all via `make` or `make all`.

Make sure that your changes follow the quality standards described below.

### 1️⃣ Lint

Runs [luacheck](https://github.com/lunarmodules/luacheck/) using `.luacheck` settings:

```
make lint
```

### 2️⃣ Style

Runs [StyLua](https://github.com/JohnnyMorganz/StyLua) using `.stylua.toml` settings:

```
make format-check
```

You can automatically fix [StyLua](https://github.com/JohnnyMorganz/StyLua) issues using:

```
make format
```

### 3️⃣ LSP Check

Runs [LuaLS](https://github.com/LuaLS/lua-language-server) to perform LSP check inside Neovim using `.luarc.json`:

```
make lsp-check
```

### 4️⃣ Help Check

Runs [lemmy-help](https://github.com/numToStr/lemmy-help) to generate the documentation and checks if there are any changes.

```
make help-check
```

Each function and module is documented in the help. Therefore, it is required to remain up-to-date.

After introducing changes, you can update the help by calling:

```
make help-update
```

### 5️⃣ Unit Tests

Runs unit tests located in `./specs` directory using:

```
make test
```

If you are working on changes that are related to some business logic rather than integration with other tools,
make sure to cover them with tests.

To run tests you need to install [plenary.nvim](https://github.com/nvim-lua/plenary.nvim) and then you
can either run them from Neovim by using:

```
:PlenaryBustedDirectory specs/
```

or by calling

```
make test
```

The second option is recommended because it is using `minimal_init.lua` so the results shouldn't be affected by your environment.

## Style Guide

This project is not fully consistent with the style, but it will improve in the future :). However, I set some general rules:

1. Functions are named using snake_case.
2. `local` variables, function arguments, and fields are named using `camelCase`.
3. The main plugin options are named using `snake_case`.
4. Constants are named using `SNAKE_CASE`.
5. Functions that don't make sense to be exposed outside of the module should be `local`, placed at the top of the file.
6. Each function should be documented using appropriate annotations: [check here](https://github.com/numToStr/lemmy-help/blob/master/emmylua.md).
7. Avoid abbreviations like `idx`, use `index` instead.
8. Use meaningful names like `testResults` instead of `table`/`items`.
9. Watch out for cyclical `require`! If you need some module only in one place prefer putting `require` inside the function.
10. Common `require` like `xcodebuild.util`, `xcodebuild.helpers`, `xcodebuild.core.config`, `xcodebuild.core.constants`,
    `xcodebuild.project.appdata`, `xcodebuild.broadcasting.events`, `xcodebuild.broadcasting.notifications`,
    and `xcodebuild.project.config` you can keep at the top because they are meant to be used in multiple places.
11. To name commits please follow [Conventional Commits](https://www.conventionalcommits.org).

Example of a local function:

```lua
---Validates if test plan is set in the project configuration.
---Send an error notification if not found.
---@return boolean
local function validate_testplan()
  if not projectConfig.settings.testPlan then
    notifications.send_error("Test plan not found. Please run XcodebuildSelectTestPlan")
    return false
  end

  return true
end
```

Example of a public function:

```lua
---Filters an array based on a {predicate} function.
---@param table any[]
---@param predicate fun(value: any): boolean
---@return any[]
function M.filter(table, predicate)
  local result = {}
  for _, value in ipairs(table) do
    if predicate(value) then
      table.insert(result, value)
    end
  end

  return result
end
```

Prefer `local function` over `local xyz = function`:

```lua
-- Good
local function validate_testplan()
end

-- Bad
local validate_testplan = function()
end
```

## Adding New Feature

It all depends on what you are going to implement. However, below will give you a general guideline on how to extend the current
functionality assuming that you want to add a new action to the commands picker related to `xcodebuild` tool.

In this case, you would need to:

1. Implement the feature in a desired module. In this example, in `core/xcode.lua`. Make sure that the function is documented and
   connected types are defined using annotations.
2. Define a new action in `actions.lua`.
3. Add a new action to the main picker in `ui/pickers.lua`.
4. Define a user command connected to this action in `init.lua`.
5. Update `README.md` by adding this command.
6. Update `docs/commands.lua` by adding this command.
7. Add tests to `specs` if it makes sense.
8. Run `make format help-update` and then `make all` to check if everything is OK.

If you want to extend the default options:

1. Add the new option to `core/config.lua`.
2. Update `README.md`.
3. Update annotation over `M.setup` in `init.lua`.
4. Run `make format help-update` and then `make all` to check if everything is OK.

Modules you will most likely need in development:

- `xcodebuild.core.config` to access the plugin's options
- `xcodebuild.project.config` to access the current project configuration
- `xcodebuild.project.appdata` to access files and tools stored in `.nvim/xcodebuild` folder
- `xcodebuild.project.builder` to build the app
- `xcodebuild.tests.runner` to run tests
- `xcodebuild.platform.device` to interact with a device or simulator
- `xcodebuild.ui.pickers` to show some picker
- `xcodebuild.broadcasting.notifications` to send notifications to user
- `xcodebuild.util` lua helpers
- `xcodebuild.helpers` plugin helpers

#### Good luck and have fun! 🚀
