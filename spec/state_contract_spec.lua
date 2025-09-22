describe('State module contracts', function()
  local cp
  local state
  local logged_messages
  local original_scrape_problem
  local original_scrape_contest_metadata
  local original_cache_get_test_cases

  before_each(function()
    logged_messages = {}
    local mock_logger = {
      log = function(msg, level)
        table.insert(logged_messages, { msg = msg, level = level })
      end,
      set_config = function() end,
    }
    package.loaded['cp.log'] = mock_logger

    -- Mock scraping to avoid network calls
    original_scrape_problem = package.loaded['cp.scrape']
    package.loaded['cp.scrape'] = {
      scrape_problem = function(ctx)
        return {
          success = true,
          problem_id = ctx.problem_id,
          test_cases = {
            { input = 'test input', expected = 'test output' },
          },
          test_count = 1,
        }
      end,
      scrape_contest_metadata = function(platform, contest_id)
        return {
          success = true,
          problems = {
            { id = 'a' },
            { id = 'b' },
            { id = 'c' },
          },
        }
      end,
      scrape_problems_parallel = function()
        return {}
      end,
    }

    -- Mock cache to avoid file system
    local cache = require('cp.cache')
    original_cache_get_test_cases = cache.get_test_cases
    cache.get_test_cases = function(platform, contest_id, problem_id)
      -- Return some mock test cases
      return {
        { input = 'mock input', expected = 'mock output' },
      }
    end

    -- Mock cache load/save to be no-ops
    cache.load = function() end
    cache.set_test_cases = function() end
    cache.set_file_state = function() end
    cache.get_file_state = function()
      return nil
    end
    cache.get_contest_data = function()
      return nil
    end

    -- Mock vim functions that might not exist in test
    if not vim.fn then
      vim.fn = {}
    end
    vim.fn.expand = vim.fn.expand or function()
      return '/tmp/test.cpp'
    end
    vim.fn.mkdir = vim.fn.mkdir or function() end
    vim.fn.fnamemodify = vim.fn.fnamemodify or function(path)
      return path
    end
    vim.fn.tempname = vim.fn.tempname or function()
      return '/tmp/session'
    end
    if not vim.api then
      vim.api = {}
    end
    vim.api.nvim_get_current_buf = vim.api.nvim_get_current_buf or function()
      return 1
    end
    vim.api.nvim_buf_get_lines = vim.api.nvim_buf_get_lines
      or function()
        return { '' }
      end
    if not vim.cmd then
      vim.cmd = {}
    end
    vim.cmd.e = function() end
    vim.cmd.only = function() end
    vim.cmd.split = function() end
    vim.cmd.vsplit = function() end
    if not vim.system then
      vim.system = function(cmd)
        return {
          wait = function()
            return { code = 0 }
          end,
        }
      end
    end

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
    if original_scrape_problem then
      package.loaded['cp.scrape'] = original_scrape_problem
    end
    if original_cache_get_test_cases then
      local cache = require('cp.cache')
      cache.get_test_cases = original_cache_get_test_cases
    end
    if state then
      state.reset()
    end
  end)

  it('should enforce that all modules use state getters, not direct properties', function()
    local state_module = require('cp.state')

    -- State module should expose getter functions
    assert.equals('function', type(state_module.get_platform))
    assert.equals('function', type(state_module.get_contest_id))
    assert.equals('function', type(state_module.get_problem_id))

    -- State module should NOT expose internal state properties directly
    -- (This prevents the bug we just fixed)
    assert.is_nil(state_module.platform)
    assert.is_nil(state_module.contest_id)
    assert.is_nil(state_module.problem_id)
  end)

  it('should maintain state consistency between context and direct access', function()
    -- Set up a problem
    cp.handle_command({ fargs = { 'codeforces', '1234', 'a' } })

    -- Get context through public API
    local context = cp.get_current_context()

    -- Get values through state module directly
    local direct_access = {
      platform = state.get_platform(),
      contest_id = state.get_contest_id(),
      problem_id = state.get_problem_id(),
    }

    -- These should be identical
    assert.equals(context.platform, direct_access.platform)
    assert.equals(context.contest_id, direct_access.contest_id)
    assert.equals(context.problem_id, direct_access.problem_id)
  end)

  it('should handle nil state values gracefully in all consumers', function()
    -- Start with clean state (all nil)
    state.reset()

    -- This should NOT crash with "expected string, got nil"
    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'run' } })
    end)

    -- Should log appropriate error, not validation error
    local has_validation_error = false
    local has_appropriate_error = false
    for _, log_entry in ipairs(logged_messages) do
      if log_entry.msg:match('expected string, got nil') then
        has_validation_error = true
      elseif log_entry.msg:match('No contest configured') then
        has_appropriate_error = true
      end
    end

    assert.is_false(has_validation_error, 'Should not have validation errors')
    assert.is_true(has_appropriate_error, 'Should have appropriate user-facing error')
  end)

  it('should pass state module (not state data) to runner functions', function()
    -- This is the core bug we fixed - runner expects state module, not state data
    local run = require('cp.runner.run')
    local problem = require('cp.problem')

    -- Set up proper state
    state.set_platform('codeforces')
    state.set_contest_id('1234')
    state.set_problem_id('a')

    local ctx = problem.create_context('codeforces', '1234', 'a', {
      contests = { codeforces = { cpp = { extension = 'cpp' } } },
    })

    -- This should work - passing the state MODULE
    assert.has_no_errors(function()
      run.load_test_cases(ctx, state)
    end)

    -- This would be the bug - passing state DATA instead of state MODULE
    local fake_state_data = {
      platform = 'codeforces',
      contest_id = '1234',
      problem_id = 'a',
    }

    -- This should fail gracefully (function should check for get_* methods)
    local success = pcall(function()
      run.load_test_cases(ctx, fake_state_data)
    end)

    -- The current implementation would crash because fake_state_data has no get_* methods
    -- This test documents the expected behavior
    assert.is_false(success, 'Should fail when passed wrong state type')
  end)

  it('should handle state transitions correctly', function()
    -- Test that state changes are reflected everywhere

    -- Initial state
    cp.handle_command({ fargs = { 'codeforces', '1234', 'a' } })
    assert.equals('a', cp.get_current_context().problem_id)

    -- Navigate to next problem
    cp.handle_command({ fargs = { 'codeforces', '1234', 'b' } })
    assert.equals('b', cp.get_current_context().problem_id)

    -- State should be consistent everywhere
    assert.equals('b', state.get_problem_id())
  end)
end)
