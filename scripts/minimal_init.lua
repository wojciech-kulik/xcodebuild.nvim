local M = {}

---@param root string|nil
---@return string
function M.root(root)
  local f = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(f, ":p:h:h") .. "/" .. (root or "")
end

---@param plugin string
function M.install(plugin)
  local name = plugin:match(".*/(.*)")
  local package_root = M.root(".tests/site/pack/deps/start/")
  if not vim.loop.fs_stat(package_root .. name) then
    print("Installing " .. plugin)
    vim.fn.mkdir(package_root, "p")
    vim.fn.system({
      "git",
      "clone",
      "--depth=1",
      "https://github.com/" .. plugin .. ".git",
      package_root .. "/" .. name,
    })
  end
end

function M.setup()
  vim.cmd([[set runtimepath=$VIMRUNTIME]])
  vim.opt.runtimepath:append(M.root())
  vim.opt.packpath = { M.root(".tests/site") }
  vim.env.XDG_CONFIG_HOME = M.root(".tests/config")
  vim.env.XDG_DATA_HOME = M.root(".tests/data")
  vim.env.XDG_STATE_HOME = M.root(".tests/state")
  vim.env.XDG_CACHE_HOME = M.root(".tests/cache")

  M.install("nvim-lua/plenary.nvim")
  M.install("nvim-treesitter/nvim-treesitter")

  vim.cmd([[packadd plenary.nvim]])
  vim.cmd([[packadd nvim-treesitter]])

  local parserFileExists =
    vim.loop.fs_stat(M.root(".tests/site/pack/deps/start/nvim-treesitter/parser/swift.so"))

  ---@diagnostic disable-next-line: missing-fields
  require("nvim-treesitter.configs").setup({})

  if not parserFileExists then
    print("Installing Swift parser")

    vim.fn.mkdir(M.root(".tests/site/pack/deps/start/nvim-treesitter/parser"), "p")
    vim.fn.system({
      "cp",
      M.root("scripts/swift.so"),
      M.root(".tests/site/pack/deps/start/nvim-treesitter/parser/swift.so"),
    })
  end
end

M.setup()
