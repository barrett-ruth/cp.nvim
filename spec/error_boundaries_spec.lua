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

    package.loaded['cp.scraper'] = {
      scrape_problem_tests = function(_, contest_id, problem_id, callback)
        if contest_id == 'fail_scrape' then
          callback({
            success = false,
            error = 'Network error',
          })
          return
        end
        callback({
          success = true,
          problem_id = problem_id,
          tests = {
            { input = '1', expected = '2' },
          },
        })
      end,
      scrape_contest_metadata = function(_, contest_id, callback)
        if contest_id == 'fail_scrape' then
          callback({
            success = false,
            error = 'Network error',
          })
          return
        end
        if contest_id == 'fail_metadata' then
          callback({
            success = false,
            error = 'Contest not found',
          })
          return
        end
        callback({
          success = true,
          problems = {
            { id = 'a' },
            { id = 'b' },
          },
        })
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
      vim.system = function(_)
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
    package.loaded['cp.scraper'] = nil
    if state then
      state.reset()
    end
  end)

  it('should handle scraping failures without state corruption', function()
    cp.handle_command({ fargs = { 'codeforces', 'fail_scrape', 'a' } })

    vim.wait(100)

    local has_metadata_error = false
    for _, log_entry in ipairs(logged_messages) do
      if log_entry.msg and log_entry.msg:match('failed to load contest metadata') then
        has_metadata_error = true
        break
      end
    end
    assert.is_true(has_metadata_error, 'Should log contest metadata failure')

    assert.equals('codeforces', state.get_platform())

    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'run' } })
    end)
  end)

  it('should handle missing contest data without crashing navigation', function()
    state.set_platform('codeforces')
    state.set_contest_id('nonexistent')
    state.set_problem_id('a')

    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'next' } })
    end)

    local has_nav_error = false
    for _, log_entry in ipairs(logged_messages) do
      if log_entry.msg and log_entry.msg:match('no contest data available') then
        has_nav_error = true
        break
      end
    end
    assert.is_true(has_nav_error, 'Should log navigation error')
  end)

  it('should handle validation errors without crashing', function()
    state.reset()

    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'next' } })
    end)

    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'prev' } })
    end)

    -- assert.has_no_errors(function()
    --   cp.handle_command({ fargs = { 'run' } })
    -- end)

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
    state.set_platform('codeforces')

    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'run' } })
    end)

    assert.has_no_errors(function()
      cp.handle_command({ fargs = { 'next' } })
    end)

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
end)
