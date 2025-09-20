describe('cp.execute', function()
  local execute
  local mock_system_calls
  local temp_files
  local spec_helper = require('spec.spec_helper')

  before_each(function()
    spec_helper.setup()
    execute = require('cp.execute')
    mock_system_calls = {}
    temp_files = {}

    vim.system = function(cmd, opts)
      table.insert(mock_system_calls, { cmd = cmd, opts = opts })
      if not cmd or #cmd == 0 then
        return {
          wait = function()
            return { code = 0, stdout = '', stderr = '' }
          end,
        }
      end

      local result = { code = 0, stdout = '', stderr = '' }

      if cmd[1] == 'mkdir' then
        result = { code = 0 }
      elseif cmd[1] == 'g++' or cmd[1] == 'gcc' then
        result = { code = 0, stderr = '' }
      elseif cmd[1]:match('%.run$') or cmd[1] == 'python' then
        result = { code = 0, stdout = '42\n', stderr = '' }
      end

      return {
        wait = function()
          return result
        end,
      }
    end

    local original_fn = vim.fn
    vim.fn = vim.tbl_extend('force', vim.fn, {
      filereadable = function(path)
        return temp_files[path] and 1 or 0
      end,
      readfile = function(path)
        return temp_files[path] or {}
      end,
      fnamemodify = function(path, modifier)
        if modifier == ':e' then
          return path:match('%.([^.]+)$') or ''
        end
        return original_fn.fnamemodify(path, modifier)
      end,
    })

    vim.uv = vim.tbl_extend('force', vim.uv or {}, {
      hrtime = function()
        return 1000000000
      end,
    })
  end)

  after_each(function()
    vim.system = vim.system_original or vim.system
    spec_helper.teardown()
    temp_files = {}
  end)

  describe('template substitution', function()
    it('substitutes placeholders correctly', function()
      local language_config = {
        compile = { 'g++', '{source_file}', '-o', '{binary_file}' },
      }
      local substitutions = {
        source_file = 'test.cpp',
        binary_file = 'test.run',
      }

      local result = execute.compile_generic(language_config, substitutions)

      assert.equals(0, result.code)
      assert.is_true(#mock_system_calls > 0)

      local compile_call = mock_system_calls[1]
      assert.equals('sh', compile_call.cmd[1])
      assert.equals('-c', compile_call.cmd[2])
      assert.is_not_nil(string.find(compile_call.cmd[3], 'g\\+\\+ test\\.cpp %-o test\\.run'))
      assert.is_not_nil(string.find(compile_call.cmd[3], '2>&1'))
    end)

    it('handles multiple substitutions in single argument', function()
      local language_config = {
        compile = { 'g++', '{source_file}', '-o{binary_file}' },
      }
      local substitutions = {
        source_file = 'main.cpp',
        binary_file = 'main.out',
      }

      execute.compile_generic(language_config, substitutions)

      local compile_call = mock_system_calls[1]
      assert.is_not_nil(string.find(compile_call.cmd[3], '%-omain\\.out'))
    end)
  end)

  describe('compilation', function()
    it('skips compilation when not required', function()
      local language_config = {}
      local substitutions = {}

      local result = execute.compile_generic(language_config, substitutions)

      assert.equals(0, result.code)
      assert.equals('', result.stderr)
      assert.equals(0, #mock_system_calls)
    end)

    it('compiles cpp files correctly', function()
      local language_config = {
        compile = { 'g++', '{source_file}', '-o', '{binary_file}', '-std=c++17' },
      }
      local substitutions = {
        source_file = 'solution.cpp',
        binary_file = 'build/solution.run',
      }

      local result = execute.compile_generic(language_config, substitutions)

      assert.equals(0, result.code)
      assert.is_true(#mock_system_calls > 0)

      local compile_call = mock_system_calls[1]
      assert.equals('sh', compile_call.cmd[1])
      assert.is_not_nil(string.find(compile_call.cmd[3], '%-std=c\\+\\+17'))
    end)

    it('handles compilation errors gracefully', function()
      vim.system = function()
        return {
          wait = function()
            return { code = 1, stderr = 'error: undefined variable' }
          end,
        }
      end

      local language_config = {
        compile = { 'g++', '{source_file}', '-o', '{binary_file}' },
      }
      local substitutions = { source_file = 'bad.cpp', binary_file = 'bad.run' }

      local result = execute.compile_generic(language_config, substitutions)

      assert.equals(1, result.code)
      assert.is_not_nil(result.stderr:match('undefined variable'))
    end)

    it('measures compilation time', function()
      local start_time = 1000000000
      local end_time = 1500000000
      local call_count = 0

      vim.uv.hrtime = function()
        call_count = call_count + 1
        if call_count == 1 then
          return start_time
        else
          return end_time
        end
      end

      local language_config = {
        compile = { 'g++', 'test.cpp', '-o', 'test.run' },
      }

      execute.compile_generic(language_config, {})
      assert.is_true(call_count >= 2)
    end)
  end)

  describe('test execution', function()
    it('executes commands with input data', function()
      vim.system = function(cmd, opts)
        table.insert(mock_system_calls, { cmd = cmd, opts = opts })
        return {
          wait = function()
            return { code = 0, stdout = '3\n', stderr = '' }
          end,
        }
      end

      local language_config = {
        run = { '{binary_file}' },
      }

      execute.compile_generic(language_config, { binary_file = './test.run' })
    end)

    it('handles command execution', function()
      vim.system = function(_, opts)
        if opts then
          assert.equals(false, opts.text)
        end
        return {
          wait = function()
            return { code = 124, stdout = '', stderr = '' }
          end,
        }
      end

      local language_config = {
        compile = { 'timeout', '1', 'sleep', '2' },
      }

      local result = execute.compile_generic(language_config, {})
      assert.equals(124, result.code)
    end)

    it('captures stderr output', function()
      vim.system = function()
        return {
          wait = function()
            return { code = 1, stdout = '', stderr = 'runtime error\n' }
          end,
        }
      end

      local language_config = {
        compile = { 'false' },
      }

      local result = execute.compile_generic(language_config, {})
      assert.equals(1, result.code)
      assert.is_not_nil(result.stderr:match('runtime error'))
    end)
  end)

  describe('parameter validation', function()
    it('validates language_config parameter', function()
      assert.has_error(function()
        execute.compile_generic(nil, {})
      end)

      assert.has_error(function()
        execute.compile_generic('not_table', {})
      end)
    end)

    it('validates substitutions parameter', function()
      assert.has_error(function()
        execute.compile_generic({}, nil)
      end)

      assert.has_error(function()
        execute.compile_generic({}, 'not_table')
      end)
    end)
  end)

  describe('directory creation', function()
    it('creates build and io directories', function()
      local language_config = {
        compile = { 'mkdir', '-p', 'build', 'io' },
      }

      execute.compile_generic(language_config, {})

      local mkdir_call = mock_system_calls[1]
      assert.equals('sh', mkdir_call.cmd[1])
      assert.is_not_nil(string.find(mkdir_call.cmd[3], 'mkdir'))
      assert.is_not_nil(string.find(mkdir_call.cmd[3], 'build'))
      assert.is_not_nil(string.find(mkdir_call.cmd[3], 'io'))
    end)
  end)

  describe('language detection', function()
    it('detects cpp from extension', function()
      vim.fn.fnamemodify = function()
        return 'cpp'
      end

      assert.has_no_errors(function()
        execute.compile_generic({}, {})
      end)
    end)

    it('falls back to default language', function()
      vim.fn.fnamemodify = function(_, modifier)
        if modifier == ':e' then
          return 'unknown'
        end
        return ''
      end

      assert.has_no_errors(function()
        execute.compile_generic({}, {})
      end)
    end)
  end)

  describe('edge cases', function()
    it('handles empty command templates', function()
      local language_config = {
        compile = {},
      }

      local result = execute.compile_generic(language_config, {})
      assert.equals(0, result.code)
    end)

    it('handles commands with no substitutions needed', function()
      local language_config = {
        compile = { 'echo', 'hello' },
      }

      local result = execute.compile_generic(language_config, {})
      assert.equals(0, result.code)

      local echo_call = mock_system_calls[1]
      assert.equals('sh', echo_call.cmd[1])
      assert.is_not_nil(string.find(echo_call.cmd[3], 'echo hello'))
    end)

    it('handles multiple consecutive substitutions', function()
      local language_config = {
        compile = { '{compiler}{compiler}', '{file}{file}' },
      }
      local substitutions = {
        compiler = 'g++',
        file = 'test.cpp',
      }

      execute.compile_generic(language_config, substitutions)

      local call = mock_system_calls[1]
      assert.equals('sh', call.cmd[1])
      assert.is_not_nil(string.find(call.cmd[3], 'g\\+\\+g\\+\\+ test\\.cpptest\\.cpp'))
    end)
  end)

  describe('stderr/stdout redirection', function()
    it('should use stderr redirection (2>&1)', function()
      local original_system = vim.system
      local captured_command = nil

      vim.system = function(cmd, opts)
        captured_command = cmd
        return {
          wait = function()
            return { code = 0, stdout = '', stderr = '' }
          end,
        }
      end

      local language_config = {
        compile = { 'g++', '-std=c++17', '-o', '{binary}', '{source}' },
      }
      local substitutions = { source = 'test.cpp', binary = 'build/test', version = '17' }
      execute.compile_generic(language_config, substitutions)

      assert.is_not_nil(captured_command)
      assert.equals('sh', captured_command[1])
      assert.equals('-c', captured_command[2])
      assert.is_not_nil(
        string.find(captured_command[3], '2>&1'),
        'Command should contain 2>&1 redirection'
      )

      vim.system = original_system
    end)

    it('should return combined stdout+stderr in result', function()
      local original_system = vim.system
      local test_output = 'STDOUT: Hello\nSTDERR: Error message\n'

      vim.system = function(cmd, opts)
        return {
          wait = function()
            return { code = 1, stdout = test_output, stderr = '' }
          end,
        }
      end

      local language_config = {
        compile = { 'g++', '-std=c++17', '-o', '{binary}', '{source}' },
      }
      local substitutions = { source = 'test.cpp', binary = 'build/test', version = '17' }
      local result = execute.compile_generic(language_config, substitutions)

      assert.equals(1, result.code)
      assert.equals(test_output, result.stdout)

      vim.system = original_system
    end)
  end)

  describe('integration tests', function()
    it('captures interleaved stderr/stdout with ANSI colors', function()
      local start_time = vim.uv.hrtime()
      local python_cmd = {
        'sh',
        '-c',
        "python3 -c \"import sys; print('\\033[32mstdout: \\033[1mSuccess\\033[0m'); print('\\033[31mstderr: \\033[1mWarning\\033[0m', file=sys.stderr); print('plain stdout')\" 2>&1",
      }
      local result = vim.system(python_cmd, { timeout = 2000, text = false }):wait()
      local execution_time = (vim.uv.hrtime() - start_time) / 1000000

      local ansi = require('cp.ansi')
      local combined_output = ansi.bytes_to_string(result.stdout or '')

      assert.equals(0, result.code)
      assert.is_not_nil(string.find(combined_output, 'stdout:'))
      assert.is_not_nil(string.find(combined_output, 'stderr:'))
      assert.is_not_nil(string.find(combined_output, 'plain stdout'))

      local parsed = ansi.parse_ansi_text(combined_output)
      local clean_text = table.concat(parsed.lines, '\n')

      assert.is_not_nil(string.find(clean_text, 'Success'))
      assert.is_not_nil(string.find(clean_text, 'Warning'))

      local has_green = false
      local has_red = false
      local has_bold = false

      for _, highlight in ipairs(parsed.highlights) do
        if string.find(highlight.highlight_group, 'Green') then
          has_green = true
        end
        if string.find(highlight.highlight_group, 'Red') then
          has_red = true
        end
        if string.find(highlight.highlight_group, 'Bold') then
          has_bold = true
        end
      end

      assert.is_true(has_green, 'Should have green highlights')
      assert.is_true(has_red, 'Should have red highlights')
      assert.is_true(has_bold, 'Should have bold highlights')
    end)

    it('handles script failures with combined output', function()
      local python_cmd = {
        'sh',
        '-c',
        "python3 -c \"import sys; print('Starting...'); print('ERROR: Something failed', file=sys.stderr); sys.exit(1)\" 2>&1",
      }
      local result = vim.system(python_cmd, { timeout = 2000, text = false }):wait()

      assert.is_not_equals(0, result.code)

      local ansi = require('cp.ansi')
      local combined_output = ansi.bytes_to_string(result.stdout or '')
      assert.is_not_nil(string.find(combined_output, 'Starting'))
      assert.is_not_nil(string.find(combined_output, 'ERROR'))

      local parsed = ansi.parse_ansi_text(combined_output)
      local clean_text = table.concat(parsed.lines, '\n')
      assert.is_not_nil(string.find(clean_text, 'Something failed'))
    end)
  end)
end)
