describe('run module ANSI processing', function()
  local run = require('cp.run')
  local config = require('cp.config')

  describe('ANSI processing modes', function()
    it('parses ANSI when ansi config is true', function()
      local test_config = config.setup({ run_panel = { ansi = true } })

      local result = {
        stdout = 'Hello \027[31mworld\027[0m!',
        stderr = '',
        code = 0,
        ok = true,
        signal = nil,
        timed_out = false,
      }

      local processed = run.process_test_result(result, 'expected_output', test_config)

      assert.equals('Hello world!', processed.actual)
      assert.equals(1, #processed.actual_highlights)
      assert.equals('CpAnsiRed', processed.actual_highlights[1].highlight_group)
    end)

    it('strips ANSI when ansi config is false', function()
      local test_config = config.setup({ run_panel = { ansi = false } })

      local result = {
        stdout = 'Hello \027[31mworld\027[0m!',
        stderr = '',
        code = 0,
        ok = true,
        signal = nil,
        timed_out = false,
      }

      local processed = run.process_test_result(result, 'expected_output', test_config)

      assert.equals('Hello world!', processed.actual)
      assert.equals(0, #processed.actual_highlights)
    end)

    it('handles compilation failure with ansi disabled', function()
      local test_config = config.setup({ run_panel = { ansi = false } })

      local compilation_output = 'error.cpp:1:1: \027[1m\027[31merror:\027[0m undefined variable'

      -- Create mock run panel state
      run._test_set_panel_state({
        test_cases = {
          { index = 1, input = 'test', expected = 'expected' },
        },
      })

      run.handle_compilation_failure(compilation_output)

      local panel_state = run.get_run_panel_state()
      local test_case = panel_state.test_cases[1]

      assert.equals('error.cpp:1:1: error: undefined variable', test_case.actual)
      assert.equals(0, #test_case.actual_highlights)
      assert.equals('Compilation failed', test_case.error)
    end)
  end)
end)
