local M = {}

function M.log(msg, level, override)
  level = level or vim.log.levels.INFO
  if level >= vim.log.levels.WARN or override then
    vim.notify(('[cp.nvim]: %s'):format(msg), level)
  end
end

return M
