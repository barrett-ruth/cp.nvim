---@class RanTestCase
---@field index number
---@field input string
---@field expected string
---@field status "pending"|"pass"|"fail"|"running"|"tle"|"mle"
---@field actual string?
---@field actual_highlights? Highlight[]
---@field time_ms number?
---@field error string?
---@field stderr string?
---@field selected boolean
---@field code number?
---@field ok boolean?
---@field signal string?
---@field tled boolean?
---@field mled boolean?

---@class ProblemConstraints
---@field timeout_ms number
---@field memory_mb number

---@class RunPanelState
---@field test_cases RanTestCase[]
---@field current_index number
---@field buffer number?
---@field namespace number?
---@field is_active boolean
---@field saved_layout table?
---@field constraints ProblemConstraints?

local M = {}
local cache = require('cp.cache')
local constants = require('cp.constants')
local logger = require('cp.log')

---@type RunPanelState
local run_panel_state = {
  test_cases = {},
  current_index = 1,
  buffer = nil,
  namespace = nil,
  is_active = false,
  saved_layout = nil,
  constraints = nil,
}

local function load_constraints_from_cache(platform, contest_id, problem_id)
  cache.load()
  local timeout_ms, memory_mb = cache.get_constraints(platform, contest_id, problem_id)
  if timeout_ms and memory_mb then
    return { timeout_ms = timeout_ms, memory_mb = memory_mb }
  end
  return nil
end

local function create_sentinal_panel_data(test_cases)
  local out = {}
  for i, tc in ipairs(test_cases) do
    out[i] = {
      index = tc.index or i,
      input = tc.input or '',
      expected = tc.expected or '',
      status = 'pending',
      selected = false,
    }
  end
  return out
end

local function build_command(language_config, substitutions)
  local exec_util = require('cp.runner.execute')._util
  return exec_util.build_command(language_config.test, language_config.executable, substitutions)
end

local function run_single_test_case(contest_config, cp_config, test_case)
  local state = require('cp.state')
  local exec = require('cp.runner.execute')

  local source_file = state.get_source_file()
  local ext = vim.fn.fnamemodify(source_file or '', ':e')
  local lang_name = constants.filetype_to_language[ext] or contest_config.default_language
  local language_config = contest_config[lang_name]

  local binary_file = state.get_binary_file()
  local substitutions = { source = source_file, binary = binary_file }

  if language_config.compile and binary_file and vim.fn.filereadable(binary_file) == 0 then
    local cr = exec.compile(language_config, substitutions)
    local ansi = require('cp.ui.ansi')
    local clean = ansi.bytes_to_string(cr.stdout or '')
    if cr.code ~= 0 then
      return {
        status = 'fail',
        actual = clean,
        actual_highlights = {},
        error = 'Compilation failed',
        stderr = clean,
        time_ms = 0,
        code = cr.code,
        ok = false,
        signal = nil,
        tled = false,
        mled = false,
      }
    end
  end

  local cmd = build_command(language_config, substitutions)
  local stdin_content = (test_case.input or '') .. '\n'
  local timeout_ms = (run_panel_state.constraints and run_panel_state.constraints.timeout_ms)
    or 2000
  local memory_mb = run_panel_state.constraints and run_panel_state.constraints.memory_mb or nil

  local r = exec.run(cmd, stdin_content, timeout_ms, memory_mb)

  local ansi = require('cp.ui.ansi')
  local out = (r.stdout or ''):gsub('\n$', '')

  local highlights = {}
  if out ~= '' then
    if cp_config.run_panel.ansi then
      local parsed = ansi.parse_ansi_text(out)
      out = table.concat(parsed.lines, '\n')
      highlights = parsed.highlights
    else
      out = out:gsub('\027%[[%d;]*[a-zA-Z]', '')
    end
  end

  local max_lines = cp_config.run_panel.max_output_lines
  local lines = vim.split(out, '\n')
  if #lines > max_lines then
    local trimmed = {}
    for i = 1, max_lines do
      table.insert(trimmed, lines[i])
    end
    table.insert(trimmed, string.format('... (output trimmed after %d lines)', max_lines))
    out = table.concat(trimmed, '\n')
  end

  local expected = (test_case.expected or ''):gsub('\n$', '')
  local ok = out == expected

  local signal = r.signal
  if not signal and r.code and r.code >= 128 then
    signal = constants.signal_codes[r.code]
  end

  local status
  if r.tled then
    status = 'tle'
  elseif r.mled then
    status = 'mle'
  elseif ok then
    status = 'pass'
  else
    status = 'fail'
  end

  return {
    status = status,
    actual = out,
    actual_highlights = highlights,
    error = (r.code ~= 0 and not ok) and out or nil,
    stderr = '',
    time_ms = r.time_ms,
    code = r.code,
    ok = ok,
    signal = signal,
    tled = r.tled or false,
    mled = r.mled or false,
  }
end

function M.load_test_cases(state)
  local tcs = cache.get_test_cases(
    state.get_platform() or '',
    state.get_contest_id() or '',
    state.get_problem_id()
  )

  run_panel_state.test_cases = create_sentinal_panel_data(tcs)
  run_panel_state.current_index = 1
  run_panel_state.constraints = load_constraints_from_cache(
    state.get_platform() or '',
    state.get_contest_id() or '',
    state.get_problem_id()
  )

  logger.log(('Loaded %d test case(s)'):format(#tcs), vim.log.levels.INFO)
  return #tcs > 0
end

function M.run_test_case(contest_config, cp_config, index)
  local tc = run_panel_state.test_cases[index]
  if not tc then
    return false
  end

  tc.status = 'running'
  local r = run_single_test_case(contest_config, cp_config, tc)

  tc.status = r.status
  tc.actual = r.actual
  tc.actual_highlights = r.actual_highlights
  tc.error = r.error
  tc.stderr = r.stderr
  tc.time_ms = r.time_ms
  tc.code = r.code
  tc.ok = r.ok
  tc.signal = r.signal
  tc.tled = r.tled
  tc.mled = r.mled

  return true
end

function M.run_all_test_cases(contest_config, cp_config)
  local results = {}
  for i = 1, #run_panel_state.test_cases do
    M.run_test_case(contest_config, cp_config, i)
    results[i] = run_panel_state.test_cases[i]
  end
  return results
end

function M.get_run_panel_state()
  return run_panel_state
end

function M.handle_compilation_failure(compilation_output)
  local ansi = require('cp.ui.ansi')
  local config = require('cp.config').setup()

  local txt
  local hl = {}

  if config.run_panel.ansi then
    local p = ansi.parse_ansi_text(compilation_output or '')
    txt = table.concat(p.lines, '\n')
    hl = p.highlights
  else
    txt = (compilation_output or ''):gsub('\027%[[%d;]*[a-zA-Z]', '')
  end

  for _, tc in ipairs(run_panel_state.test_cases) do
    tc.status = 'fail'
    tc.actual = txt
    tc.actual_highlights = hl
    tc.error = 'Compilation failed'
    tc.stderr = ''
    tc.time_ms = 0
    tc.code = 1
    tc.ok = false
    tc.signal = nil
    tc.tled = false
    tc.mled = false
  end
end

return M
