local M = {}

local config_module = require('cp.config')
local logger = require('cp.log')
local snippets = require('cp.snippets')

if vim.fn.has('nvim-0.10.0') == 0 then
  logger.log('Requires nvim-0.10.0+', vim.log.levels.ERROR)
  return {}
end

local user_config = {}
local config = nil
local snippets_initialized = false
local initialized = false

--- Root handler for all `:CP ...` commands
---@return nil
function M.handle_command(opts)
  local commands = require('cp.commands')
  commands.handle_command(opts)
end

function M.setup(opts)
  opts = opts or {}
  user_config = opts
  config = config_module.setup(user_config)
  config_module.set_current_config(config)

  if not snippets_initialized then
    snippets.setup(config)
    snippets_initialized = true
  end
  initialized = true
end

function M.is_initialized()
  return initialized
end

return M
