local M = {}

function M.create_buffer_with_options(filetype)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = buf })
  vim.api.nvim_set_option_value('readonly', true, { buf = buf })
  vim.api.nvim_set_option_value('modifiable', false, { buf = buf })
  if filetype then
    vim.api.nvim_set_option_value('filetype', filetype, { buf = buf })
  end
  return buf
end

function M.update_buffer_content(bufnr, lines, highlights, namespace)
  local was_readonly = vim.api.nvim_get_option_value('readonly', { buf = bufnr })

  vim.api.nvim_set_option_value('readonly', false, { buf = bufnr })
  vim.api.nvim_set_option_value('modifiable', true, { buf = bufnr })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = bufnr })
  vim.api.nvim_set_option_value('readonly', was_readonly, { buf = bufnr })

  if highlights and namespace then
    local highlight = require('cp.ui.highlight')
    highlight.apply_highlights(bufnr, highlights, namespace)
  end
end

return M
