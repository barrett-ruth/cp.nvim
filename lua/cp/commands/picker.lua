local M = {}

local config_module = require('cp.config')
local logger = require('cp.log')

function M.handle_pick_action()
  local config = config_module.get_config()

  if not config.picker then
    logger.log(
      'No picker configured. Set picker = "telescope" or picker = "fzf-lua" in config',
      vim.log.levels.ERROR
    )
    return
  end

  if config.picker == 'telescope' then
    local ok = pcall(require, 'telescope')
    if not ok then
      logger.log(
        'Telescope not available. Install telescope.nvim or change picker config',
        vim.log.levels.ERROR
      )
      return
    end
    local ok_cp, telescope_cp = pcall(require, 'cp.pickers.telescope')
    if not ok_cp then
      logger.log('Failed to load telescope integration', vim.log.levels.ERROR)
      return
    end
    telescope_cp.platform_picker()
  elseif config.picker == 'fzf-lua' then
    local ok, _ = pcall(require, 'fzf-lua')
    if not ok then
      logger.log(
        'fzf-lua not available. Install fzf-lua or change picker config',
        vim.log.levels.ERROR
      )
      return
    end
    local ok_cp, fzf_cp = pcall(require, 'cp.pickers.fzf_lua')
    if not ok_cp then
      logger.log('Failed to load fzf-lua integration', vim.log.levels.ERROR)
      return
    end
    fzf_cp.platform_picker()
  end
end

return M
