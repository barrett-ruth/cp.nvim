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

---Pad text on the right (left-align text within width)
---@param text string
---@param width integer
---@return string
function M.pad_right(text, width)
  local pad = width - #text
  if pad <= 0 then
    return text
  end
  return text .. string.rep(' ', pad)
end

---Pad text on the left (right-align text within width)
---@param text string
---@param width integer
---@return string
function M.pad_left(text, width)
  local pad = width - #text
  if pad <= 0 then
    return text
  end
  return string.rep(' ', pad) .. text
end

---Center text within width
---@param text string
---@param width integer
---@return string
function M.center(text, width)
  local pad = width - #text
  if pad <= 0 then
    return text
  end
  local left = math.ceil(pad / 2)
  return string.rep(' ', left) .. text .. string.rep(' ', pad - left)
end

---Default verdict formatter for I/O view
---@param data VerdictFormatData
---@return VerdictFormatResult
function M.default_verdict_formatter(data)
  local time_actual = string.format('%.2f', data.time_ms)
  local time_limit = tostring(data.time_limit_ms)
  local mem_actual = string.format('%.0f', data.memory_mb)
  local mem_limit = string.format('%.0f', data.memory_limit_mb)
  local exit_str = data.signal and string.format('%d (%s)', data.exit_code, data.signal)
    or tostring(data.exit_code)

  -- Use dynamic widths if provided, otherwise use reasonable defaults
  local time_actual_w = data.time_actual_width or 6
  local time_limit_w = data.time_limit_width or 4
  local mem_actual_w = data.mem_actual_width or 3
  local mem_limit_w = data.mem_limit_width or 3

  local test_num_part = 'Test ' .. data.index .. ':'
  local status_part = M.pad_right(data.status.text, 3)
  local time_part = M.pad_left(time_actual, time_actual_w)
    .. '/'
    .. M.pad_left(time_limit, time_limit_w)
    .. ' ms'
  local mem_part = M.pad_left(mem_actual, mem_actual_w)
    .. '/'
    .. M.pad_left(mem_limit, mem_limit_w)
    .. ' MB'
  local exit_part = 'exit: ' .. exit_str

  local line = test_num_part
    .. ' '
    .. status_part
    .. ' | '
    .. time_part
    .. ' | '
    .. mem_part
    .. ' | '
    .. exit_part

  local highlights = {}
  local status_pos = line:find(data.status.text, 1, true)
  if status_pos then
    table.insert(highlights, {
      col_start = status_pos - 1,
      col_end = status_pos - 1 + #data.status.text,
      group = data.status.highlight_group,
    })
  end

  return { line = line, highlights = highlights }
end

return M
