local M = {}

local cache = require('cp.cache')
local constants = require('cp.constants')
local logger = require('cp.log')

local platforms = constants.PLATFORMS

--- Dispatch any `:CP cache ...` command
---@param cmd table
---@return nil
function M.handle_cache_command(cmd)
  if cmd.subcommand == 'read' then
    local data = cache.get_data_pretty()
    local name = 'cp.nvim://cache.lua'

    local existing = vim.fn.bufnr(name)
    local buf
    if existing ~= -1 then
      buf = existing
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(data, '\n'))
    else
      buf = vim.api.nvim_create_buf(true, true)
      vim.api.nvim_buf_set_name(buf, name)
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(data, '\n'))
      vim.bo[buf].filetype = 'lua'
      vim.bo[buf].buftype = 'nofile'
      vim.bo[buf].bufhidden = 'wipe'
      vim.bo[buf].swapfile = false
      vim.api.nvim_buf_set_keymap(
        buf,
        'n',
        'q',
        '<cmd>bd!<cr>',
        { nowait = true, noremap = true, silent = true }
      )
    end

    vim.api.nvim_set_current_buf(buf)
  elseif cmd.subcommand == 'clear' then
    cache.load()
    if cmd.platform then
      if vim.tbl_contains(platforms, cmd.platform) then
        cache.clear_platform(cmd.platform)
        logger.log(
          ("Cache cleared for platform '%s'"):format(constants.PLATFORM_DISPLAY_NAMES[cmd.platform]),
          vim.log.levels.INFO,
          true
        )
      else
        logger.log(("Unknown platform '%s'."):format(cmd.platform), vim.log.levels.ERROR)
      end
    else
      cache.clear_all()
      logger.log('Cache cleared', vim.log.levels.INFO, true)
    end
  end
end

return M
