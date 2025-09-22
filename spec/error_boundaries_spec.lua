describe('Error boundary handling', function()
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

    -- Mock dependencies that could fail
    package.loaded['cp.scrape'] = {
      scrape_problem = function(ctx)
        -- Sometimes fail to simulate network issues
        if ctx.contest_id == 'fail_scrape' then
          return {
            success = false,
            error = 'Network error',
          }
        end
        return {
          success = true,
          problem_id = ctx.problem_id,
          test_cases = {
            { input = '1', expected = '2' },
          },
          test_count = 1,
        }
      end,
      scrape_contest_metadata = function(platform, contest_id)
        if contest_id == 'fail_metadata' then
          return {
            success = false,
            error = 'Contest not found',
          }
        end
        return {
          success = true,
          problems = {
            { id = 'a' },
            { id = 'b' },
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
    cache.get_contest_data = function()
      return nil
    end
    cache.get_test_cases = function()
      return {}
    end

    -- Mock vim functions
    if not vim.fn then
      vim.fn = {}
    end
    vim.fn.expand = vim.fn.expand or function()
      return '/tmp/test.cpp'
    end
    vim.fn.mkdir = vim.fn.mkdir or function() end
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

  it('should handle setup failures gracefully without breaking runner', function()
    -- Try invalid platform
    cp.handle_command({ fargs = { 'invalid_platform', '1234', 'a' } })

    -- Should have logged error
    local has_error = false
    for _, log_entry in ipairs(logged_messages) do
      if log_entry.level == vim.log.levels.ERROR then
        has_error = true
        break
      end
    end
    assert.is_true(has_error, 'Should log error for invalid platform')

    -- State should remain clean
    local context = cp.get_current_context()
    assert.is_nil(context.platform)

    -- Runner should handle this gracefully
    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'run' } }) -- Should log error, not crash
    end)
  end)

  it('should handle scraping failures without state corruption', function()
    -- Setup should fail due to scraping failure
    cp.handle_command({ fargs = { 'codeforces', 'fail_scrape', 'a' } })

    -- Should have logged scraping error
    local has_scrape_error = false
    for _, log_entry in ipairs(logged_messages) do
      if log_entry.msg and log_entry.msg:match('scraping failed') then
        has_scrape_error = true
        break
      end
    end
    assert.is_true(has_scrape_error, 'Should log scraping failure')

    -- State should still be set (platform and contest)
    local context = cp.get_current_context()
    assert.equals('codeforces', context.platform)
    assert.equals('fail_scrape', context.contest_id)

    -- But should handle run gracefully
    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'run' } })
    end)
  end)

  it('should handle missing contest data without crashing navigation', function()
    -- Setup with valid platform but no contest data
    state.set_platform('codeforces')
    state.set_contest_id('nonexistent')
    state.set_problem_id('a')

    -- Navigation should fail gracefully
    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'next' } })
    end)

    -- Should log appropriate error
    local has_nav_error = false
    for _, log_entry in ipairs(logged_messages) do
      if log_entry.msg and log_entry.msg:match('no contest metadata found') then
        has_nav_error = true
        break
      end
    end
    assert.is_true(has_nav_error, 'Should log navigation error')
  end)

  it('should handle validation errors without crashing', function()
    -- This would previously cause validation errors
    state.reset() -- All state is nil

    -- Commands should handle nil state gracefully
    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'next' } })
    end)

    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'prev' } })
    end)

    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'run' } })
    end)

    -- Should have appropriate errors, not validation errors
    local has_validation_error = false
    local has_appropriate_errors = 0
    for _, log_entry in ipairs(logged_messages) do
      if log_entry.msg and log_entry.msg:match('expected string, got nil') then
        has_validation_error = true
      elseif
        log_entry.msg
        and (log_entry.msg:match('no contest set') or log_entry.msg:match('No contest configured'))
      then
        has_appropriate_errors = has_appropriate_errors + 1
      end
    end

    assert.is_false(has_validation_error, 'Should not have validation errors')
    assert.is_true(has_appropriate_errors > 0, 'Should have user-facing errors')
  end)

  it('should handle partial state gracefully', function()
    -- Set only platform, not contest
    state.set_platform('codeforces')

    -- Commands should handle partial state
    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'run' } })
    end)

    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'next' } })
    end)

    -- Should get appropriate errors about missing contest
    local missing_contest_errors = 0
    for _, log_entry in ipairs(logged_messages) do
      if
        log_entry.msg and (log_entry.msg:match('no contest') or log_entry.msg:match('No contest'))
      then
        missing_contest_errors = missing_contest_errors + 1
      end
    end
    assert.is_true(missing_contest_errors > 0, 'Should report missing contest')
  end)

  it('should isolate command parsing errors from execution', function()
    -- Test malformed commands
    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'cache' } }) -- Missing subcommand
    end)

    assert.has_no_errors(function()
      cp.handle_command({ fargs = { '--lang' } }) -- Missing value
    end)

    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'too', 'many', 'args', 'here', 'extra' } })
    end)

    -- All should result in error messages, not crashes
    assert.is_true(#logged_messages > 0, 'Should have logged errors')

    local crash_count = 0
    for _, log_entry in ipairs(logged_messages) do
      if log_entry.msg and log_entry.msg:match('stack traceback') then
        crash_count = crash_count + 1
      end
    end
    assert.equals(0, crash_count, 'Should not have any crashes')
  end)

  it('should handle module loading failures gracefully', function()
    -- Test with missing optional dependencies
    local original_picker_module = package.loaded['cp.commands.picker']
    package.loaded['cp.commands.picker'] = nil

    -- Pick command should handle missing module
    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'pick' } })
    end)

    package.loaded['cp.commands.picker'] = original_picker_module
  end)
end)
