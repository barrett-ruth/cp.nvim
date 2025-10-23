local M = {}

---@param bufnr integer
function M.clearcol(bufnr)
  for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
    vim.wo[win].signcolumn = 'no'
    vim.wo[win].statuscolumn = ''
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
  end
end

return M
