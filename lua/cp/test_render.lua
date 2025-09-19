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

---Convert test status to CP terminology with colors
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
  if signal_name then
    return string.format('%d (%s)', code, signal_name)
  else
    return tostring(code)
  end
end

local function calculate_column_widths(test_state)
  local widths = { num = 3, status = 6, time = 4, exit = 4 }

  for i, test_case in ipairs(test_state.test_cases) do
    local prefix = i == test_state.current_index and '>' or ' '
    local num_text = string.format('%s%d', prefix, i)
    widths.num = math.max(widths.num, #num_text)

    local status_info = M.get_status_info(test_case)
    widths.status = math.max(widths.status, #status_info.text)

    local time_text = test_case.time_ms and string.format('%dms', test_case.time_ms) or '—'
    widths.time = math.max(widths.time, #time_text)

    local exit_text = format_exit_code(test_case.code)
    widths.exit = math.max(widths.exit, #exit_text)
  end

  return widths
end

local function create_separator(widths)
  local parts = {
    string.rep('─', widths.num),
    string.rep('─', widths.status),
    string.rep('─', widths.time),
    string.rep('─', widths.exit),
  }
  return table.concat(parts, '┼')
end

---Render test cases as a clean table
---@param test_state TestPanelState
---@return string[], table[] lines and highlight positions
function M.render_test_list(test_state)
  local lines = {}
  local highlights = {}

  local widths = calculate_column_widths(test_state)
  local separator = create_separator(widths)

  local header = string.format(
    '%-*s│%-*s│%-*s│%-*s',
    widths.num,
    ' #',
    widths.status,
    ' Status',
    widths.time,
    ' Time',
    widths.exit,
    ' Exit Code'
  )

  table.insert(lines, header)
  table.insert(lines, separator)

  for i, test_case in ipairs(test_state.test_cases) do
    local is_current = i == test_state.current_index
    local prefix = is_current and '>' or ' '
    local status_info = M.get_status_info(test_case)

    local num_text = string.format('%s%d', prefix, i)
    local time_text = test_case.time_ms and string.format('%dms', test_case.time_ms) or '—'
    local exit_text = format_exit_code(test_case.code)

    local row = string.format(
      '%-*s│ %-*s│%-*s│ %-*s',
      widths.num,
      num_text,
      widths.status - 1,
      status_info.text,
      widths.time,
      time_text,
      widths.exit - 1,
      exit_text
    )

    table.insert(lines, row)

    if status_info.text ~= '' then
      local status_start = widths.num + 2
      local status_end = status_start + #status_info.text
      table.insert(highlights, {
        line = #lines - 1,
        col_start = status_start,
        col_end = status_end,
        highlight_group = status_info.highlight_group,
      })
    end

    if is_current and test_case.input and test_case.input ~= '' then
      table.insert(lines, separator)
      for _, input_line in
        ipairs(vim.split(test_case.input, '\n', { plain = true, trimempty = false }))
      do
        table.insert(lines, input_line)
      end
    end

    table.insert(lines, separator)
  end

  return lines, highlights
end

---Create status bar content for diff pane
---@param test_case TestCase?
---@return string
function M.render_status_bar(test_case)
  if not test_case then
    return ''
  end

  local parts = {}

  if test_case.time_ms then
    table.insert(parts, string.format('%.0fms', test_case.time_ms))
  end

  if test_case.code then
    table.insert(parts, string.format('Exit: %d', test_case.code))
  end

  return table.concat(parts, ' │ ')
end

---Get highlight groups needed for test rendering
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

---Setup highlight groups
function M.setup_highlights()
  local groups = M.get_highlight_groups()
  for group_name, opts in pairs(groups) do
    vim.api.nvim_set_hl(0, group_name, opts)
  end
end

return M
