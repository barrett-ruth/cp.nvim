local execute = require('cp.execute')

describe('execute module', function()
  local test_ctx
  local test_config

  before_each(function()
    test_ctx = {
      source_file = 'test.cpp',
      binary_file = 'build/test',
      input_file = 'io/test.cpin',
      output_file = 'io/test.cpout',
    }

    test_config = {
      default_language = 'cpp',
      cpp = {
        version = 17,
        compile = { 'g++', '-std=c++17', '-o', '{binary}', '{source}' },
        test = { '{binary}' },
        executable = nil,
      },
    }
  end)

  describe('compile_generic', function()
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

      local substitutions = { source = 'test.cpp', binary = 'build/test', version = '17' }
      execute.compile_generic(test_config.cpp, substitutions)

      assert.is_not_nil(captured_command)
      assert.equals('sh', captured_command[1])
      assert.equals('-c', captured_command[2])
      assert.is_true(
        string.find(captured_command[3], '2>&1') ~= nil,
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

      local substitutions = { source = 'test.cpp', binary = 'build/test', version = '17' }
      local result = execute.compile_generic(test_config.cpp, substitutions)

      assert.equals(1, result.code)
      assert.equals(test_output, result.stdout)

      vim.system = original_system
    end)
  end)

  describe('compile_problem', function()
    it('should return combined output in stderr field for compatibility', function()
      local original_system = vim.system
      local test_error_output = 'test.cpp:1:1: error: expected declaration\n'

      vim.system = function(cmd, opts)
        return {
          wait = function()
            return { code = 1, stdout = test_error_output, stderr = '' }
          end,
        }
      end

      local result = execute.compile_problem(test_ctx, test_config, false)

      assert.is_false(result.success)
      assert.equals(test_error_output, result.output)

      vim.system = original_system
    end)

    it('should return success=true when compilation succeeds', function()
      local original_system = vim.system

      vim.system = function(cmd, opts)
        return {
          wait = function()
            return { code = 0, stdout = '', stderr = '' }
          end,
        }
      end

      local result = execute.compile_problem(test_ctx, test_config, false)

      assert.is_true(result.success)
      assert.is_nil(result.output)

      vim.system = original_system
    end)
  end)
end)
