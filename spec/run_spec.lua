describe('run module', function()
  local run = require('cp.run')

  describe('basic functionality', function()
    it('has required functions', function()
      assert.is_function(run.load_test_cases)
      assert.is_function(run.run_test_case)
      assert.is_function(run.run_all_test_cases)
      assert.is_function(run.get_run_panel_state)
      assert.is_function(run.handle_compilation_failure)
    end)

    it('can get panel state', function()
      local state = run.get_run_panel_state()
      assert.is_table(state)
      assert.is_table(state.test_cases)
    end)

    it('handles compilation failure', function()
      local compilation_output = 'error.cpp:1:1: error: undefined variable'

      assert.does_not_error(function()
        run.handle_compilation_failure(compilation_output)
      end)
    end)
  end)
end)
