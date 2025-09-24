local M = {}

function M.log(msg, level, override)
  level = level or vim.log.levels.INFO
  if level >= vim.log.levels.WARN or override then
    vim.schedule(function()
      vim.notify(('[cp.nvim]: %s'):format(msg), level)
    end)
  end
end

function M.progress(msg)
  vim.schedule(function()
    vim.notify(('[cp.nvim]: %s'):format(msg), vim.log.levels.INFO)
  end)
end

return M
