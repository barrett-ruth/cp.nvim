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

function M.pad_right(text, width)
  local pad = width - #text
  if pad <= 0 then
    return text
  end
  return text .. string.rep(' ', pad)
end

function M.pad_left(text, width)
  local pad = width - #text
  if pad <= 0 then
    return text
  end
  return string.rep(' ', pad) .. text
end

function M.center(text, width)
  local pad = width - #text
  if pad <= 0 then
    return text
  end
  local left = math.ceil(pad / 2)
  return string.rep(' ', left) .. text .. string.rep(' ', pad - left)
end

return M
