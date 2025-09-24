---@class ExecuteResult
---@field stdout string
---@field stderr string
---@field code integer
---@field time_ms number
---@field timed_out boolean

local M = {}
local logger = require('cp.log')

local constants = require('cp.constants')
local filetype_to_language = constants.filetype_to_language

---@param source_file string
---@param contest_config table
---@return string
local function get_language_from_file(source_file, contest_config)
  vim.validate({
    source_file = { source_file, 'string' },
    contest_config = { contest_config, 'table' },
  })

  local extension = vim.fn.fnamemodify(source_file, ':e')
  local language = filetype_to_language[extension] or contest_config.default_language
  return language
end

---@param cmd_template string[]
---@param substitutions table<string, string>
---@return string[]
local function substitute_template(cmd_template, substitutions)
  vim.validate({
    cmd_template = { cmd_template, 'table' },
    substitutions = { substitutions, 'table' },
  })

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

---@param cmd_template string[]
---@param executable? string
---@param substitutions table<string, string>
---@return string[]
local function build_command(cmd_template, executable, substitutions)
  vim.validate({
    cmd_template = { cmd_template, 'table' },
    executable = { executable, { 'string', 'nil' }, true },
    substitutions = { substitutions, 'table' },
  })

  local cmd = substitute_template(cmd_template, substitutions)
  if executable then
    table.insert(cmd, 1, executable)
  end
  return cmd
end

---@param language_config table
---@param substitutions table<string, string>
---@return {code: integer, stdout: string, stderr: string}
function M.compile_generic(language_config, substitutions)
  vim.validate({
    language_config = { language_config, 'table' },
    substitutions = { substitutions, 'table' },
  })

  if not language_config.compile then
    logger.log('no compilation step required')
    return { code = 0, stderr = '' }
  end

  local compile_cmd = substitute_template(language_config.compile, substitutions)
  local redirected_cmd = vim.deepcopy(compile_cmd)
  if #redirected_cmd > 0 then
    redirected_cmd[#redirected_cmd] = redirected_cmd[#redirected_cmd] .. ' 2>&1'
  end

  local start_time = vim.uv.hrtime()
  local result = vim
    .system({ 'sh', '-c', table.concat(redirected_cmd, ' ') }, { text = false })
    :wait()
  local compile_time = (vim.uv.hrtime() - start_time) / 1000000

  local ansi = require('cp.ui.ansi')
  result.stdout = ansi.bytes_to_string(result.stdout or '')
  result.stderr = ansi.bytes_to_string(result.stderr or '')

  if result.code == 0 then
    logger.log(('compilation successful (%.1fms)'):format(compile_time), vim.log.levels.INFO)
  else
    logger.log(('compilation failed (%.1fms)'):format(compile_time))
  end

  return result
end

---@param cmd string[]
---@param input_data string
---@param timeout_ms number
---@return ExecuteResult
local function execute_command(cmd, input_data, timeout_ms)
  vim.validate({
    cmd = { cmd, 'table' },
    input_data = { input_data, 'string' },
    timeout_ms = { timeout_ms, 'number' },
  })

  local redirected_cmd = vim.deepcopy(cmd)
  if #redirected_cmd > 0 then
    redirected_cmd[#redirected_cmd] = redirected_cmd[#redirected_cmd] .. ' 2>&1'
  end

  local start_time = vim.uv.hrtime()

  local result = vim
    .system({ 'sh', '-c', table.concat(redirected_cmd, ' ') }, {
      stdin = input_data,
      timeout = timeout_ms,
      text = true,
    })
    :wait()

  local end_time = vim.uv.hrtime()
  local execution_time = (end_time - start_time) / 1000000

  local actual_code = result.code or 0

  if result.code == 124 then
    logger.log(('execution timed out after %.1fms'):format(execution_time), vim.log.levels.WARN)
  elseif actual_code ~= 0 then
    logger.log(
      ('execution failed (exit code %d, %.1fms)'):format(actual_code, execution_time),
      vim.log.levels.WARN
    )
  else
    logger.log(('execution successful (%.1fms)'):format(execution_time))
  end

  return {
    stdout = result.stdout or '',
    stderr = result.stderr or '',
    code = actual_code,
    time_ms = execution_time,
    timed_out = result.code == 124,
  }
end

---@param exec_result ExecuteResult
---@param expected_file string
---@param is_debug boolean
---@return string
local function format_output(exec_result, expected_file, is_debug)
  vim.validate({
    exec_result = { exec_result, 'table' },
    expected_file = { expected_file, 'string' },
    is_debug = { is_debug, 'boolean' },
  })

  local output_lines = { exec_result.stdout }
  local metadata_lines = {}

  if exec_result.timed_out then
    table.insert(metadata_lines, '[code]: 124 (TIMEOUT)')
  elseif exec_result.code >= 128 then
    local signal_name = constants.signal_codes[exec_result.code] or 'SIGNAL'
    table.insert(metadata_lines, ('[code]: %d (%s)'):format(exec_result.code, signal_name))
  else
    table.insert(metadata_lines, ('[code]: %d'):format(exec_result.code))
  end

  table.insert(metadata_lines, ('[time]: %.2f ms'):format(exec_result.time_ms))
  table.insert(metadata_lines, ('[debug]: %s'):format(is_debug and 'true' or 'false'))

  if vim.fn.filereadable(expected_file) == 1 and exec_result.code == 0 then
    local expected_content = vim.fn.readfile(expected_file)
    local actual_lines = vim.split(exec_result.stdout, '\n')

    while #actual_lines > 0 and actual_lines[#actual_lines] == '' do
      table.remove(actual_lines)
    end

    local ok = #actual_lines == #expected_content
    if ok then
      for i, line in ipairs(actual_lines) do
        if line ~= expected_content[i] then
          ok = false
          break
        end
      end
    end

    table.insert(metadata_lines, ('[ok]: %s'):format(ok and 'true' or 'false'))
  end

  return table.concat(output_lines, '') .. '\n' .. table.concat(metadata_lines, '\n')
end

---@param contest_config ContestConfig
---@param is_debug? boolean
---@return {success: boolean, output: string?}
function M.compile_problem(contest_config, is_debug)
  vim.validate({
    contest_config = { contest_config, 'table' },
  })

  local state = require('cp.state')
  local source_file = state.get_source_file()
  if not source_file then
    logger.log('No source file found', vim.log.levels.ERROR)
    return { success = false, output = 'No source file found' }
  end

  local language = get_language_from_file(source_file, contest_config)
  local language_config = contest_config[language]

  if not language_config then
    logger.log('No configuration for language: ' .. language, vim.log.levels.ERROR)
    return { success = false, output = 'No configuration for language: ' .. language }
  end

  local binary_file = state.get_binary_file()
  local substitutions = {
    source = source_file,
    binary = binary_file,
  }

  local compile_cmd = (is_debug and language_config.debug) and language_config.debug
    or language_config.compile
  if compile_cmd then
    language_config.compile = compile_cmd
    local compile_result = M.compile_generic(language_config, substitutions)
    if compile_result.code ~= 0 then
      return { success = false, output = compile_result.stdout or 'unknown error' }
    end
    logger.log(
      ('compilation successful (%s)'):format(is_debug and 'debug mode' or 'test mode'),
      vim.log.levels.INFO
    )
  end

  return { success = true, output = nil }
end

function M.run_problem(contest_config, is_debug)
  vim.validate({
    contest_config = { contest_config, 'table' },
    is_debug = { is_debug, 'boolean' },
  })

  local state = require('cp.state')
  local source_file = state.get_source_file()
  local output_file = state.get_output_file()

  if not source_file or not output_file then
    logger.log('Missing required file paths', vim.log.levels.ERROR)
    return
  end

  vim.system({ 'mkdir', '-p', 'build', 'io' }):wait()

  local language = get_language_from_file(source_file, contest_config)
  local language_config = contest_config[language]

  if not language_config then
    vim.fn.writefile({ 'Error: No configuration for language: ' .. language }, output_file)
    return
  end

  local binary_file = state.get_binary_file()
  local substitutions = {
    source = source_file,
    binary = binary_file,
  }

  local compile_cmd = is_debug and language_config.debug or language_config.compile
  if compile_cmd then
    local compile_result = M.compile_generic(language_config, substitutions)
    if compile_result.code ~= 0 then
      vim.fn.writefile({ compile_result.stderr }, output_file)
      return
    end
  end

  local input_file = state.get_input_file()
  local input_data = ''
  if input_file and vim.fn.filereadable(input_file) == 1 then
    input_data = table.concat(vim.fn.readfile(input_file), '\n') .. '\n'
  end

  local cache = require('cp.cache')
  cache.load()
  local platform = state.get_platform()
  local contest_id = state.get_contest_id()
  local problem_id = state.get_problem_id()

  if not platform or not contest_id then
    logger.log('configure a contest before running a problem', vim.log.levels.ERROR)
    return
  end
  local timeout_ms, _ = cache.get_constraints(platform, contest_id, problem_id)
  timeout_ms = timeout_ms or 2000

  local run_cmd = build_command(language_config.test, language_config.executable, substitutions)
  local exec_result = execute_command(run_cmd, input_data, timeout_ms)
  local expected_file = state.get_expected_file()
  local formatted_output = format_output(exec_result, expected_file, is_debug)

  local output_buf = vim.fn.bufnr(output_file)
  if output_buf ~= -1 then
    local was_modifiable = vim.api.nvim_get_option_value('modifiable', { buf = output_buf })
    local was_readonly = vim.api.nvim_get_option_value('readonly', { buf = output_buf })
    vim.api.nvim_set_option_value('readonly', false, { buf = output_buf })
    vim.api.nvim_set_option_value('modifiable', true, { buf = output_buf })
    vim.api.nvim_buf_set_lines(output_buf, 0, -1, false, vim.split(formatted_output, '\n'))
    vim.api.nvim_set_option_value('modifiable', was_modifiable, { buf = output_buf })
    vim.api.nvim_set_option_value('readonly', was_readonly, { buf = output_buf })
    vim.api.nvim_buf_call(output_buf, function()
      vim.cmd.write()
    end)
  else
    vim.fn.writefile(vim.split(formatted_output, '\n'), output_file)
  end
end

return M
