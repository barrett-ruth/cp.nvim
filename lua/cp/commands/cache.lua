local M = {}

local cache = require('cp.cache')
local constants = require('cp.constants')
local logger = require('cp.log')

local platforms = constants.PLATFORMS

function M.handle_cache_command(cmd)
  cmd.platform = cmd.platform:lower()
  if cmd.subcommand == 'clear' then
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
