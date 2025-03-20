all: lint format-check lsp-check help-check test

# Checks warnings and errors in code using linter
lint:
	luacheck -q lua

# Formats code
format:
	stylua lua

# Checks if code is formatted
format-check:
	stylua --check lua

# Checks errors in code using LSP
lsp-check:
	scripts/luals-check.sh

# Check if help is up-to-date
help-check:
	scripts/help-update.sh
	git diff --exit-code doc/xcodebuild.txt

# Updates help file
help-update:
	scripts/help-update.sh
	git add doc/xcodebuild.txt

# Runs tests
test:
	 nvim --headless --noplugin -u scripts/minimal_init.lua -c "PlenaryBustedDirectory specs/ { minimal_init = './scripts/minimal_init.lua' }"

# Installs dependencies for plugin usage
install:
	brew update --quiet
	brew install --quiet xcode-build-server xcbeautify ruby pipx rg jq coreutils
	pipx install pymobiledevice3 --quiet
	gem install --quiet xcodeproj

# Installs dependencies for development
install-dev: install
	brew install --quiet luacheck lua-language-server stylua
	cargo install lemmy-help --features=cli --quiet
