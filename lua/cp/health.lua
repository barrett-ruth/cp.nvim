local M = {}

local utils = require('cp.utils')

local function check_nvim_version()
  if vim.fn.has('nvim-0.10.0') == 1 then
    vim.health.ok('Neovim 0.10.0+ detected')
  else
    vim.health.error('cp.nvim requires Neovim 0.10.0+')
  end
end

local function check_uv()
  if vim.fn.executable('uv') == 1 then
    vim.health.ok('uv executable found')

    local result = vim.system({ 'uv', '--version' }, { text = true }):wait()
    if result.code == 0 then
      vim.health.info('uv version: ' .. result.stdout:gsub('\n', ''))
    end
  else
    vim.health.warn('uv not found - install from https://docs.astral.sh/uv/ for problem scraping')
  end
end

local function check_python_env()
  local plugin_path = utils.get_plugin_path()
  local venv_dir = plugin_path .. '/.venv'

  if vim.fn.isdirectory(venv_dir) == 1 then
    vim.health.ok('Python virtual environment found at ' .. venv_dir)
  else
    vim.health.warn('Python virtual environment not set up - run :CP command to initialize')
  end
end

local function check_luasnip()
  local has_luasnip, luasnip = pcall(require, 'luasnip')
  if has_luasnip then
    vim.health.ok('LuaSnip integration available')
    local snippet_count = #luasnip.get_snippets('all')
    vim.health.info('LuaSnip snippets loaded: ' .. snippet_count)
  else
    vim.health.info('LuaSnip not available - template expansion will be limited')
  end
end

function M.check()
  local version = require('cp.version')
  vim.health.start('cp.nvim health check')

  vim.health.info('Version: ' .. version.version)

  check_nvim_version()
  check_uv()
  check_python_env()
  check_luasnip()
end

return M
