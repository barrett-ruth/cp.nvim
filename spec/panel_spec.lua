describe('Panel integration', function()
  local cp
  local state
  local logged_messages

  before_each(function()
    logged_messages = {}
    local mock_logger = {
      log = function(msg, level)
        table.insert(logged_messages, { msg = msg, level = level })
      end,
      set_config = function() end,
    }
    package.loaded['cp.log'] = mock_logger

    -- Reset state completely
    state = require('cp.state')
    state.reset()

    cp = require('cp')
    cp.setup({
      contests = {
        codeforces = {
          default_language = 'cpp',
          cpp = { extension = 'cpp', test = { 'echo', 'test' } },
        },
      },
      scrapers = { 'codeforces' },
    })
  end)

  after_each(function()
    package.loaded['cp.log'] = nil
    if state then
      state.reset()
    end
  end)

  it('should handle run command with properly set contest context', function()
    -- First set up a contest context
    cp.handle_command({ fargs = { 'codeforces', '2146', 'b' } })

    -- Verify state was set correctly
    local context = cp.get_current_context()
    assert.equals('codeforces', context.platform)
    assert.equals('2146', context.contest_id)
    assert.equals('b', context.problem_id)

    -- Now try to run the panel - this should NOT crash with "contest_id: expected string, got nil"
    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'run' } })
    end)

    -- Should log panel opened or no test cases found, but NOT a validation error
    local has_validation_error = false
    for _, log_entry in ipairs(logged_messages) do
      if
        log_entry.level == vim.log.levels.ERROR
        and log_entry.msg:match('expected string, got nil')
      then
        has_validation_error = true
        break
      end
    end
    assert.is_false(has_validation_error)
  end)

  it('should catch state module vs state object contract violations', function()
    -- This test specifically verifies that runner functions receive the right data type
    local run = require('cp.runner.run')
    local problem = require('cp.problem')
    local config = require('cp.config')

    -- Set up state properly
    state.set_platform('codeforces')
    state.set_contest_id('2146')
    state.set_problem_id('b')

    -- Create a proper context
    local ctx = problem.create_context('codeforces', '2146', 'b', config.defaults)

    -- This should work - passing the state MODULE (not state data)
    assert.has_no_errors(function()
      run.load_test_cases(ctx, state)
    end)

    -- This would break if we passed state data instead of state module
    local fake_state_data = { platform = 'codeforces', contest_id = '2146', problem_id = 'b' }
    assert.has_errors(function()
      run.load_test_cases(ctx, fake_state_data) -- This should fail because no get_* methods
    end)
  end)
end)
