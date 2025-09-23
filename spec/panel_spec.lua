describe('Panel integration', function()
  local spec_helper = require('spec.spec_helper')
  local cp
  local state

  before_each(function()
    spec_helper.setup_full()
    spec_helper.mock_scraper_success()

    state = require('cp.state')
    state.reset()

    local mock_async_setup = {
      setup_contest_async = function() end,
      handle_full_setup_async = function(cmd)
        state.set_platform(cmd.platform)
        state.set_contest_id(cmd.contest)
        state.set_problem_id(cmd.problem)
      end,
      setup_problem_async = function() end,
    }
    package.loaded['cp.async.setup'] = mock_async_setup

    local mock_setup = {
      set_platform = function(platform)
        state.set_platform(platform)
        return true
      end,
    }
    package.loaded['cp.setup'] = mock_setup

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
    spec_helper.teardown()
    if state then
      state.reset()
    end
  end)

  it('should handle run command with properly set contest context', function()
    cp.handle_command({ fargs = { 'codeforces', '2146', 'b' } })

    local context = cp.get_current_context()
    assert.equals('codeforces', context.platform)
    assert.equals('2146', context.contest_id)
    assert.equals('b', context.problem_id)

    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'run' } })
    end)

    local has_validation_error = false
    for _, log_entry in ipairs(spec_helper.logged_messages) do
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

  it('should handle state module interface correctly', function()
    local run = require('cp.runner.run')

    state.set_platform('codeforces')
    state.set_contest_id('2146')
    state.set_problem_id('b')

    local problem = require('cp.problem')
    local config_module = require('cp.config')
    local processed_config = config_module.setup({
      contests = { codeforces = { cpp = { extension = 'cpp' } } },
    })
    local ctx = problem.create_context('codeforces', '2146', 'b', processed_config)

    assert.has_no_errors(function()
      run.load_test_cases(ctx, state)
    end)

    local fake_state_data = { platform = 'codeforces', contest_id = '2146', problem_id = 'b' }
    assert.has_errors(function()
      run.load_test_cases(ctx, fake_state_data)
    end)
  end)
end)
