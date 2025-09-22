describe('Command flow integration', function()
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

    -- Mock external dependencies
    package.loaded['cp.scrape'] = {
      scrape_problem = function(ctx)
        return {
          success = true,
          problem_id = ctx.problem_id,
          test_cases = {
            { input = '1 2', expected = '3' },
            { input = '3 4', expected = '7' },
          },
          test_count = 2,
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

    local cache = require('cp.cache')
    cache.load = function() end
    cache.set_test_cases = function() end
    cache.set_file_state = function() end
    cache.get_file_state = function()
      return nil
    end
    cache.get_contest_data = function(platform, contest_id)
      if platform == 'codeforces' and contest_id == '1234' then
        return {
          problems = {
            { id = 'a' },
            { id = 'b' },
            { id = 'c' },
          },
        }
      end
      return nil
    end
    cache.get_test_cases = function()
      return {
        { input = '1 2', expected = '3' },
      }
    end

    -- Mock vim functions
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
    if not vim.system then
      vim.system = function(cmd)
        return {
          wait = function()
            return { code = 0 }
          end,
        }
      end
    end

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
    package.loaded['cp.scrape'] = nil
    if state then
      state.reset()
    end
  end)

  it('should handle complete setup → run workflow', function()
    -- 1. Setup problem
    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'codeforces', '1234', 'a' } })
    end)

    -- 2. Verify state was set correctly
    local context = cp.get_current_context()
    assert.equals('codeforces', context.platform)
    assert.equals('1234', context.contest_id)
    assert.equals('a', context.problem_id)

    -- 3. Run panel - this is where the bug occurred
    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'run' } })
    end)

    -- Should not have validation errors
    local has_validation_error = false
    for _, log_entry in ipairs(logged_messages) do
      if log_entry.msg:match('expected string, got nil') then
        has_validation_error = true
        break
      end
    end
    assert.is_false(has_validation_error)
  end)

  it('should handle problem navigation workflow', function()
    -- 1. Setup contest
    cp.handle_command({ fargs = { 'codeforces', '1234', 'a' } })
    assert.equals('a', cp.get_current_context().problem_id)

    -- 2. Navigate to next problem
    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'next' } })
    end)
    assert.equals('b', cp.get_current_context().problem_id)

    -- 3. Navigate to previous problem
    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'prev' } })
    end)
    assert.equals('a', cp.get_current_context().problem_id)

    -- 4. Each step should be able to run panel
    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'run' } })
    end)
  end)

  it('should handle contest setup → problem switch workflow', function()
    -- 1. Setup contest (not specific problem)
    cp.handle_command({ fargs = { 'codeforces', '1234' } })
    local context = cp.get_current_context()
    assert.equals('codeforces', context.platform)
    assert.equals('1234', context.contest_id)

    -- 2. Switch to specific problem
    cp.handle_command({ fargs = { 'codeforces', '1234', 'b' } })
    assert.equals('b', cp.get_current_context().problem_id)

    -- 3. Should be able to run
    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'run' } })
    end)
  end)

  it('should handle invalid commands gracefully without state corruption', function()
    -- Setup valid state
    cp.handle_command({ fargs = { 'codeforces', '1234', 'a' } })
    local original_context = cp.get_current_context()

    -- Try invalid command
    cp.handle_command({ fargs = { 'invalid_platform', 'invalid_contest' } })

    -- State should be unchanged
    local context_after_invalid = cp.get_current_context()
    assert.equals(original_context.platform, context_after_invalid.platform)
    assert.equals(original_context.contest_id, context_after_invalid.contest_id)
    assert.equals(original_context.problem_id, context_after_invalid.problem_id)

    -- Should still be able to run
    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'run' } })
    end)
  end)

  it('should handle commands with flags correctly', function()
    -- Test language flags
    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'codeforces', '1234', 'a', '--lang=cpp' } })
    end)

    -- Test debug flags
    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'run', '--debug' } })
    end)

    -- Test combined flags
    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'run', '--lang=cpp', '--debug' } })
    end)
  end)

  it('should handle cache commands without affecting problem state', function()
    -- Setup problem
    cp.handle_command({ fargs = { 'codeforces', '1234', 'a' } })
    local original_context = cp.get_current_context()

    -- Run cache commands
    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'cache', 'clear' } })
    end)

    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'cache', 'clear', 'codeforces' } })
    end)

    -- Problem state should be unchanged
    local context_after_cache = cp.get_current_context()
    assert.equals(original_context.platform, context_after_cache.platform)
    assert.equals(original_context.contest_id, context_after_cache.contest_id)
    assert.equals(original_context.problem_id, context_after_cache.problem_id)
  end)
end)
