local M = {}

---@param bufnr integer
function M.clearcol(bufnr)
  vim.bo[bufnr].signcolumn = 'no'
  vim.bo[bufnr].statuscolumn = ''
  vim.bo[bufnr].number = false
  vim.bo[bufnr].relativenumber = false
end

return M
