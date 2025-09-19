---@class TestRenderConfig
---@field status_format "compact"|"verbose"

---@class StatusInfo
---@field text string
---@field highlight_group string

local M = {}

---Convert test status to CP terminology with colors
---@param test_case TestCase
---@return StatusInfo
local function get_status_info(test_case)
  if test_case.status == 'pass' then
    return { text = 'AC', highlight_group = 'CpTestAC' }
  elseif test_case.status == 'fail' then
    if test_case.timed_out then
      return { text = 'TLE', highlight_group = 'CpTestError' }
    elseif test_case.code and test_case.code ~= 0 then
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

---Render test cases list with improved layout
---@param test_state TestPanelState
---@param config? TestRenderConfig
---@return string[]
function M.render_test_list(test_state, config)
  config = config or { status_format = 'compact' }
  local lines = {}

  for i, test_case in ipairs(test_state.test_cases) do
    local is_current = i == test_state.current_index
    local prefix = is_current and '> ' or '  '
    local status_info = get_status_info(test_case)

    local status_text = status_info.text ~= '' and status_info.text or ''
    local line = string.format('%s%d. %s', prefix, i, status_text)

    table.insert(lines, line)

    if is_current and test_case.input and test_case.input ~= '' then
      for _, input_line in ipairs(vim.split(test_case.input, '\n', { plain = true, trimempty = false })) do
        table.insert(lines, '  ' .. input_line)
      end
    end
  end

  return lines
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
