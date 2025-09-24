---@class TestCase
---@field index number
---@field input string
---@field expected string
---@field status "pending"|"pass"|"fail"|"running"|"timeout"
---@field actual string?
---@field actual_highlights table[]?
---@field time_ms number?
---@field error string?
---@field stderr string?
---@field selected boolean
---@field code number?
---@field ok boolean?
---@field signal string?
---@field timed_out boolean?

---@class ProblemConstraints
---@field timeout_ms number
---@field memory_mb number

---@class RunPanelState
---@field test_cases TestCase[]
---@field current_index number
---@field buffer number?
---@field namespace number?
---@field is_active boolean
---@field saved_layout table?
---@field constraints ProblemConstraints?

local M = {}
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

---@param index number
---@param input string
---@param expected string
---@return TestCase
local function create_test_case(index, input, expected)
  return {
    index = index,
    input = input,
    expected = expected,
    status = 'pending',
    actual = nil,
    time_ms = nil,
    error = nil,
    selected = true,
  }
end

---@param platform string
---@param contest_id string
---@param problem_id string?
---@return TestCase[]
local function parse_test_cases_from_cache(platform, contest_id, problem_id)
  local cache = require('cp.cache')
  cache.load()
  local cached_test_cases = cache.get_test_cases(platform, contest_id, problem_id)

  if not cached_test_cases or #cached_test_cases == 0 then
    return {}
  end

  local test_cases = {}

  for i, test_case in ipairs(cached_test_cases) do
    local index = test_case.index or i
    local expected = test_case.expected or test_case.output or ''
    table.insert(test_cases, create_test_case(index, test_case.input, expected))
  end

  return test_cases
end

---@param input_file string
---@return TestCase[]
local function parse_test_cases_from_files(input_file, _)
  local base_name = vim.fn.fnamemodify(input_file, ':r')
  local test_cases = {}

  local i = 1
  while true do
    local individual_input_file = base_name .. '.' .. i .. '.cpin'
    local individual_expected_file = base_name .. '.' .. i .. '.cpout'

    if
      vim.fn.filereadable(individual_input_file) == 1
      and vim.fn.filereadable(individual_expected_file) == 1
    then
      local input_content = table.concat(vim.fn.readfile(individual_input_file), '\n')
      local expected_content = table.concat(vim.fn.readfile(individual_expected_file), '\n')

      table.insert(test_cases, create_test_case(i, input_content, expected_content))
      i = i + 1
    else
      break
    end
  end

  return test_cases
end

---@param platform string
---@param contest_id string
---@param problem_id string?
---@return ProblemConstraints?
local function load_constraints_from_cache(platform, contest_id, problem_id)
  local cache = require('cp.cache')
  cache.load()
  local timeout_ms, memory_mb = cache.get_constraints(platform, contest_id, problem_id)

  if timeout_ms and memory_mb then
    return {
      timeout_ms = timeout_ms,
      memory_mb = memory_mb,
    }
  end

  return nil
end

---@param contest_config ContestConfig
---@param test_case TestCase
---@return table
local function run_single_test_case(contest_config, cp_config, test_case)
  local state = require('cp.state')
  local source_file = state.get_source_file()
  if not source_file then
    return {
      status = 'fail',
      actual = '',
      error = 'No source file found',
      time_ms = 0,
    }
  end

  local language = vim.fn.fnamemodify(source_file, ':e')
  local language_name = constants.filetype_to_language[language] or contest_config.default_language
  local language_config = contest_config[language_name]

  if not language_config then
    return {
      status = 'fail',
      actual = '',
      error = 'No language configuration',
      time_ms = 0,
    }
  end

  local function substitute_template(cmd_template, substitutions)
    local result = {}
    for _, arg in ipairs(cmd_template) do
      local substituted = arg
      for key, value in pairs(substitutions) do
        substituted = substituted:gsub('{' .. key .. '}', value)
      end
      table.insert(result, substituted)
    end
    return result
  end

  local function build_command(cmd_template, executable, substitutions)
    local cmd = substitute_template(cmd_template, substitutions)
    if executable then
      table.insert(cmd, 1, executable)
    end
    return cmd
  end

  local binary_file = state.get_binary_file()
  local substitutions = {
    source = source_file,
    binary = binary_file,
  }

  if language_config.compile and binary_file and vim.fn.filereadable(binary_file) == 0 then
    logger.log('binary not found, compiling first...')
    local compile_cmd = substitute_template(language_config.compile, substitutions)
    local redirected_cmd = vim.deepcopy(compile_cmd)
    redirected_cmd[#redirected_cmd] = redirected_cmd[#redirected_cmd] .. ' 2>&1'
    local compile_result = vim
      .system({ 'sh', '-c', table.concat(redirected_cmd, ' ') }, { text = false })
      :wait()

    local ansi = require('cp.ui.ansi')
    compile_result.stdout = ansi.bytes_to_string(compile_result.stdout or '')
    compile_result.stderr = ansi.bytes_to_string(compile_result.stderr or '')

    if compile_result.code ~= 0 then
      return {
        status = 'fail',
        actual = '',
        error = 'Compilation failed: ' .. (compile_result.stdout or 'Unknown error'),
        stderr = compile_result.stdout or '',
        time_ms = 0,
        code = compile_result.code,
        ok = false,
        signal = nil,
        timed_out = false,
      }
    end
  end

  local run_cmd = build_command(language_config.test, language_config.executable, substitutions)

  local stdin_content = test_case.input .. '\n'

  local start_time = vim.uv.hrtime()
  local timeout_ms = run_panel_state.constraints and run_panel_state.constraints.timeout_ms or 2000

  if not run_panel_state.constraints then
    logger.log('no problem constraints available, using default 2000ms timeout')
  end
  local redirected_run_cmd = vim.deepcopy(run_cmd)
  redirected_run_cmd[#redirected_run_cmd] = redirected_run_cmd[#redirected_run_cmd] .. ' 2>&1'
  local result = vim
    .system({ 'sh', '-c', table.concat(redirected_run_cmd, ' ') }, {
      stdin = stdin_content,
      timeout = timeout_ms,
      text = false,
    })
    :wait()
  local execution_time = (vim.uv.hrtime() - start_time) / 1000000

  local ansi = require('cp.ui.ansi')
  local stdout_str = ansi.bytes_to_string(result.stdout or '')
  local actual_output = stdout_str:gsub('\n$', '')

  local actual_highlights = {}

  if actual_output ~= '' then
    if cp_config.run_panel.ansi then
      local parsed = ansi.parse_ansi_text(actual_output)
      actual_output = table.concat(parsed.lines, '\n')
      actual_highlights = parsed.highlights
    else
      actual_output = actual_output:gsub('\027%[[%d;]*[a-zA-Z]', '')
    end
  end

  local max_lines = cp_config.run_panel.max_output_lines
  local output_lines = vim.split(actual_output, '\n')
  if #output_lines > max_lines then
    local trimmed_lines = {}
    for i = 1, max_lines do
      table.insert(trimmed_lines, output_lines[i])
    end
    table.insert(trimmed_lines, string.format('... (output trimmed after %d lines)', max_lines))
    actual_output = table.concat(trimmed_lines, '\n')
  end

  local expected_output = test_case.expected:gsub('\n$', '')
  local ok = actual_output == expected_output

  local status
  local timed_out = result.code == 143 or result.code == 124
  if timed_out then
    status = 'timeout'
  elseif result.code == 0 and ok then
    status = 'pass'
  else
    status = 'fail'
  end

  local signal = nil
  if result.code >= 128 then
    signal = constants.signal_codes[result.code]
  end

  return {
    status = status,
    actual = actual_output,
    actual_highlights = actual_highlights,
    error = result.code ~= 0 and actual_output or nil,
    stderr = '',
    time_ms = execution_time,
    code = result.code,
    ok = ok,
    signal = signal,
    timed_out = timed_out,
  }
end

---@param state table
---@return boolean
function M.load_test_cases(state)
  local test_cases = parse_test_cases_from_cache(
    state.get_platform() or '',
    state.get_contest_id() or '',
    state.get_problem_id()
  )

  if #test_cases == 0 then
    local input_file = state.get_input_file()
    local expected_file = state.get_expected_file()
    test_cases = parse_test_cases_from_files(input_file, expected_file)
  end

  run_panel_state.test_cases = test_cases
  run_panel_state.current_index = 1
  run_panel_state.constraints = load_constraints_from_cache(
    state.get_platform() or '',
    state.get_contest_id() or '',
    state.get_problem_id()
  )

  local constraint_info = run_panel_state.constraints
      and string.format(
        ' with %dms/%dMB limits',
        run_panel_state.constraints.timeout_ms,
        run_panel_state.constraints.memory_mb
      )
    or ''
  logger.log(('loaded %d test case(s)%s'):format(#test_cases, constraint_info), vim.log.levels.INFO)
  return #test_cases > 0
end

---@param contest_config ContestConfig
---@param index number
---@return boolean
function M.run_test_case(contest_config, cp_config, index)
  local test_case = run_panel_state.test_cases[index]
  if not test_case then
    return false
  end

  test_case.status = 'running'

  local result = run_single_test_case(contest_config, cp_config, test_case)

  test_case.status = result.status
  test_case.actual = result.actual
  test_case.actual_highlights = result.actual_highlights
  test_case.error = result.error
  test_case.stderr = result.stderr
  test_case.time_ms = result.time_ms
  test_case.code = result.code
  test_case.ok = result.ok
  test_case.signal = result.signal
  test_case.timed_out = result.timed_out

  return true
end

---@param contest_config ContestConfig
---@param cp_config cp.Config
---@return TestCase[]
function M.run_all_test_cases(contest_config, cp_config)
  local results = {}
  for i, _ in ipairs(run_panel_state.test_cases) do
    M.run_test_case(contest_config, cp_config, i)
    table.insert(results, run_panel_state.test_cases[i])
  end
  return results
end

---@return RunPanelState
function M.get_run_panel_state()
  return run_panel_state
end

function M.handle_compilation_failure(compilation_output)
  local ansi = require('cp.ui.ansi')
  local config = require('cp.config').setup()

  local clean_text
  local highlights = {}

  if config.run_panel.ansi then
    local parsed = ansi.parse_ansi_text(compilation_output or '')
    clean_text = table.concat(parsed.lines, '\n')
    highlights = parsed.highlights
  else
    clean_text = (compilation_output or ''):gsub('\027%[[%d;]*[a-zA-Z]', '')
  end

  for _, test_case in ipairs(run_panel_state.test_cases) do
    test_case.status = 'fail'
    test_case.actual = clean_text
    test_case.actual_highlights = highlights
    test_case.error = 'Compilation failed'
    test_case.stderr = ''
    test_case.time_ms = 0
    test_case.code = 1
    test_case.ok = false
    test_case.signal = nil
    test_case.timed_out = false
  end
end

return M
