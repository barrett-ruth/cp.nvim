local M = {}

local config_module = require('cp.config')
local logger = require('cp.log')

--- Dispatch `:CP pick` to appropriate picker
---@return nil
function M.handle_pick_action()
  local config = config_module.get_config()

  if not config.picker then
    logger.log(
      'No picker configured. Set picker = "{telescope,fzf-lua}" in your config.',
      vim.log.levels.ERROR
    )
    return
  end

  local picker

  if config.picker == 'telescope' then
    local ok = pcall(require, 'telescope')
    if not ok then
      logger.log(
        'telescope.nvim is not available. Install telescope.nvim xor change your picker config.',
        vim.log.levels.ERROR
      )
      return
    end
    local ok_cp, telescope_picker = pcall(require, 'cp.pickers.telescope')
    if not ok_cp then
      logger.log('Failed to load telescope integration.', vim.log.levels.ERROR)
      return
    end

    picker = telescope_picker
  elseif config.picker == 'fzf-lua' then
    local ok, _ = pcall(require, 'fzf-lua')
    if not ok then
      logger.log(
        'fzf-lua is not available. Install fzf-lua xor change your picker config',
        vim.log.levels.ERROR
      )
      return
    end
    local ok_cp, fzf_picker = pcall(require, 'cp.pickers.fzf_lua')
    if not ok_cp then
      logger.log('Failed to load fzf-lua integration.', vim.log.levels.ERROR)
      return
    end

    picker = fzf_picker
  end

  picker.pick()
end

return M
