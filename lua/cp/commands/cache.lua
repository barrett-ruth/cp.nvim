local M = {}

local cache = require('cp.cache')
local constants = require('cp.constants')
local logger = require('cp.log')

local platforms = constants.PLATFORMS

function M.handle_cache_command(cmd)
  if cmd.subcommand == 'read' then
    local data = cache.get_data_pretty()

    local buf = vim.api.nvim_create_buf(true, true)
    vim.api.nvim_buf_set_name(buf, 'cp.nvim://cache.lua')
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(data, '\n'))
    vim.bo[buf].filetype = 'lua'

    vim.api.nvim_set_current_buf(buf)
  elseif cmd.subcommand == 'clear' then
    cache.load()
    if cmd.platform then
      if vim.tbl_contains(platforms, cmd.platform) then
        cache.clear_platform(cmd.platform)
        logger.log(
          ('Cache cleared for platform %s'):format(cmd.platform),
          vim.log.levels.INFO,
          true
        )
      else
        logger.log(
          ("Unknown platform: '%s'. Available: %s"):format(
            cmd.platform,
            table.concat(platforms, ', ')
          ),
          vim.log.levels.ERROR
        )
      end
    else
      cache.clear_all()
      logger.log('Cache cleared', vim.log.levels.INFO, true)
    end
  end
end

return M
