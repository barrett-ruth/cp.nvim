---@class StatusInfo
---@field text string
---@field highlight_group string

local M = {}

local exit_code_names = {
  [128] = 'SIGHUP',
  [129] = 'SIGINT',
  [130] = 'SIGQUIT',
  [131] = 'SIGILL',
  [132] = 'SIGTRAP',
  [133] = 'SIGABRT',
  [134] = 'SIGBUS',
  [135] = 'SIGFPE',
  [136] = 'SIGKILL',
  [137] = 'SIGUSR1',
  [138] = 'SIGSEGV',
  [139] = 'SIGUSR2',
  [140] = 'SIGPIPE',
  [141] = 'SIGALRM',
  [142] = 'SIGTERM',
  [143] = 'SIGCHLD',
}

---@param test_case TestCase
---@return StatusInfo
function M.get_status_info(test_case)
  if test_case.status == 'pass' then
    return { text = 'AC', highlight_group = 'CpTestAC' }
  elseif test_case.status == 'fail' then
    if test_case.timed_out then
      return { text = 'TLE', highlight_group = 'CpTestError' }
    elseif test_case.code and test_case.code >= 128 then
      return { text = 'RTE', highlight_group = 'CpTestError' }
    else
      return { text = 'WA', highlight_group = 'CpTestError' }
    end
  elseif test_case.status == 'timeout' then
    return { text = 'TLE', highlight_group = 'CpTestError' }
  elseif test_case.status == 'running' then
    return { text = '...', highlight_group = 'CpTestPending' }
  else
    return { text = '', highlight_group = 'CpTestPending' }
  end
end

local function format_exit_code(code)
  if not code then
    return '—'
  end
  local signal_name = exit_code_names[code]
  return signal_name and string.format('%d (%s)', code, signal_name) or tostring(code)
end

local function compute_cols(test_state)
  local w = { num = 4, status = 8, time = 6, timeout = 8, memory = 8, exit = 11 }

  local timeout_str = ''
  local memory_str = ''
  if test_state.constraints then
    timeout_str = tostring(test_state.constraints.timeout_ms)
    memory_str = string.format('%.0f', test_state.constraints.memory_mb)
  else
    timeout_str = '—'
    memory_str = '—'
  end

  for i, tc in ipairs(test_state.test_cases) do
    local prefix = (i == test_state.current_index) and '>' or ' '
    w.num = math.max(w.num, #(' ' .. prefix .. i .. ' '))
    w.status = math.max(w.status, #(' ' .. M.get_status_info(tc).text .. ' '))
    local time_str = tc.time_ms and string.format('%.2f', tc.time_ms) or '—'
    w.time = math.max(w.time, #(' ' .. time_str .. ' '))
    w.timeout = math.max(w.timeout, #(' ' .. timeout_str .. ' '))
    w.memory = math.max(w.memory, #(' ' .. memory_str .. ' '))
    w.exit = math.max(w.exit, #(' ' .. format_exit_code(tc.code) .. ' '))
  end

  w.num = math.max(w.num, #' # ')
  w.status = math.max(w.status, #' Status ')
  w.time = math.max(w.time, #' Runtime (ms) ')
  w.timeout = math.max(w.timeout, #' Time (ms) ')
  w.memory = math.max(w.memory, #' Mem (MB) ')
  w.exit = math.max(w.exit, #' Exit Code ')

  local sum = w.num + w.status + w.time + w.timeout + w.memory + w.exit
  local inner = sum + 5
  local total = inner + 2
  return { w = w, sum = sum, inner = inner, total = total }
end

local function center(text, width)
  local pad = width - #text
  if pad <= 0 then
    return text
  end
  local left = math.floor(pad / 2)
  return string.rep(' ', left) .. text .. string.rep(' ', pad - left)
end

local function right_align(text, width)
  local content = (' %s '):format(text)
  local pad = width - #content
  if pad <= 0 then
    return content
  end
  return string.rep(' ', pad) .. content
end

local function format_num_column(prefix, idx, width)
  local num_str = tostring(idx)
  local content = prefix .. num_str
  local total_pad = width - #content
  local left_pad = (#num_str == 1) and 0 or math.floor(total_pad / 2)
  local right_pad = total_pad - left_pad
  return string.rep(' ', left_pad) .. content .. string.rep(' ', right_pad)
end

local function top_border(c)
  local w = c.w
  return '┌'
    .. string.rep('─', w.num)
    .. '┬'
    .. string.rep('─', w.status)
    .. '┬'
    .. string.rep('─', w.time)
    .. '┬'
    .. string.rep('─', w.timeout)
    .. '┬'
    .. string.rep('─', w.memory)
    .. '┬'
    .. string.rep('─', w.exit)
    .. '┐'
end

local function row_sep(c)
  local w = c.w
  return '├'
    .. string.rep('─', w.num)
    .. '┼'
    .. string.rep('─', w.status)
    .. '┼'
    .. string.rep('─', w.time)
    .. '┼'
    .. string.rep('─', w.timeout)
    .. '┼'
    .. string.rep('─', w.memory)
    .. '┼'
    .. string.rep('─', w.exit)
    .. '┤'
end

local function bottom_border(c)
  local w = c.w
  return '└'
    .. string.rep('─', w.num)
    .. '┴'
    .. string.rep('─', w.status)
    .. '┴'
    .. string.rep('─', w.time)
    .. '┴'
    .. string.rep('─', w.timeout)
    .. '┴'
    .. string.rep('─', w.memory)
    .. '┴'
    .. string.rep('─', w.exit)
    .. '┘'
end

local function flat_fence_above(c)
  local w = c.w
  return '├'
    .. string.rep('─', w.num)
    .. '┴'
    .. string.rep('─', w.status)
    .. '┴'
    .. string.rep('─', w.time)
    .. '┴'
    .. string.rep('─', w.timeout)
    .. '┴'
    .. string.rep('─', w.memory)
    .. '┴'
    .. string.rep('─', w.exit)
    .. '┤'
end

local function flat_fence_below(c)
  local w = c.w
  return '├'
    .. string.rep('─', w.num)
    .. '┬'
    .. string.rep('─', w.status)
    .. '┬'
    .. string.rep('─', w.time)
    .. '┬'
    .. string.rep('─', w.timeout)
    .. '┬'
    .. string.rep('─', w.memory)
    .. '┬'
    .. string.rep('─', w.exit)
    .. '┤'
end

local function flat_bottom_border(c)
  return '└' .. string.rep('─', c.inner) .. '┘'
end

local function header_line(c)
  local w = c.w
  return '│'
    .. center('#', w.num)
    .. '│'
    .. center('Status', w.status)
    .. '│'
    .. center('Runtime (ms)', w.time)
    .. '│'
    .. center('Time (ms)', w.timeout)
    .. '│'
    .. center('Mem (MB)', w.memory)
    .. '│'
    .. center('Exit Code', w.exit)
    .. '│'
end

local function data_row(c, idx, tc, is_current, test_state)
  local w = c.w
  local prefix = is_current and '>' or ' '
  local status = M.get_status_info(tc)
  local time = tc.time_ms and string.format('%.2f', tc.time_ms) or '—'
  local exit = format_exit_code(tc.code)

  local timeout = ''
  local memory = ''
  if test_state.constraints then
    timeout = tostring(test_state.constraints.timeout_ms)
    memory = string.format('%.0f', test_state.constraints.memory_mb)
  else
    timeout = '—'
    memory = '—'
  end

  local line = '│'
    .. format_num_column(prefix, idx, w.num)
    .. '│'
    .. right_align(status.text, w.status)
    .. '│'
    .. right_align(time, w.time)
    .. '│'
    .. right_align(timeout, w.timeout)
    .. '│'
    .. right_align(memory, w.memory)
    .. '│'
    .. right_align(exit, w.exit)
    .. '│'

  local hi
  if status.text ~= '' then
    local content = ' ' .. status.text .. ' '
    local pad = w.status - #content
    local status_start_col = 1 + w.num + 1 + pad + 1
    local status_end_col = status_start_col + #status.text
    hi = {
      col_start = status_start_col,
      col_end = status_end_col,
      highlight_group = status.highlight_group,
    }
  end

  return line, hi
end

---@param test_state RunPanelState
---@return string[], table[] lines and highlight positions
function M.render_test_list(test_state)
  local lines, highlights = {}, {}
  local c = compute_cols(test_state)

  table.insert(lines, top_border(c))
  table.insert(lines, header_line(c))
  table.insert(lines, row_sep(c))

  for i, tc in ipairs(test_state.test_cases) do
    local is_current = (i == test_state.current_index)
    local row, hi = data_row(c, i, tc, is_current, test_state)
    table.insert(lines, row)
    if hi then
      hi.line = #lines - 1
      table.insert(highlights, hi)
    end

    local has_next = (i < #test_state.test_cases)
    local has_input = is_current and tc.input and tc.input ~= ''

    if has_input then
      table.insert(lines, flat_fence_above(c))

      local input_header = 'Input:'
      local header_pad = c.inner - #input_header
      table.insert(lines, '│' .. input_header .. string.rep(' ', header_pad) .. '│')

      for _, input_line in ipairs(vim.split(tc.input, '\n', { plain = true, trimempty = false })) do
        local s = input_line or ''
        if #s > c.inner then
          s = string.sub(s, 1, c.inner)
        end
        local pad = c.inner - #s
        table.insert(lines, '│' .. s .. string.rep(' ', pad) .. '│')
      end

      if has_next then
        table.insert(lines, flat_fence_below(c))
      else
        table.insert(lines, flat_bottom_border(c))
      end
    else
      if has_next then
        table.insert(lines, row_sep(c))
      else
        table.insert(lines, bottom_border(c))
      end
    end
  end

  return lines, highlights
end

---@param test_case TestCase?
---@return string
function M.render_status_bar(test_case)
  if not test_case then
    return ''
  end
  local parts = {}
  if test_case.time_ms then
    table.insert(parts, string.format('%.2fms', test_case.time_ms))
  end
  if test_case.code then
    table.insert(parts, string.format('Exit: %d', test_case.code))
  end
  return table.concat(parts, ' │ ')
end

---@return table<string, table>
function M.get_highlight_groups()
  return {
    CpTestAC = { fg = '#10b981', bold = true },
    CpTestError = { fg = '#ef4444', bold = true },
    CpTestPending = { fg = '#6b7280' },
    CpDiffRemoved = { fg = '#ef4444', bg = '#1f1f1f' },
    CpDiffAdded = { fg = '#10b981', bg = '#1f1f1f' },
  }
end

function M.setup_highlights()
  local groups = M.get_highlight_groups()
  for name, opts in pairs(groups) do
    vim.api.nvim_set_hl(0, name, opts)
  end
end

return M
