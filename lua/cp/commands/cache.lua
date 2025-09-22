local M = {}

local cache = require('cp.cache')
local constants = require('cp.constants')
local logger = require('cp.log')

local platforms = constants.PLATFORMS

function M.handle_cache_command(cmd)
  if cmd.subcommand == 'clear' then
    cache.load()
    if cmd.platform then
      if vim.tbl_contains(platforms, cmd.platform) then
        cache.clear_platform(cmd.platform)
        logger.log(('cleared cache for %s'):format(cmd.platform), vim.log.levels.INFO, true)
      else
        logger.log(
          ('unknown platform: %s. Available: %s'):format(
            cmd.platform,
            table.concat(platforms, ', ')
          ),
          vim.log.levels.ERROR
        )
      end
    else
      cache.clear_all()
      logger.log('cleared all cache', vim.log.levels.INFO, true)
    end
  end
end

return M
