local M = {}

function M.log(msg, level, override)
  local debug = require('cp.config').get_config().debug or false
  level = level or vim.log.levels.INFO
  if level >= vim.log.levels.WARN or override or debug then
    vim.schedule(function()
      vim.notify(('[cp.nvim]: %s'):format(msg), level)
    end)
  end
end

return M
