describe('async integration', function()
  local cp
  local spec_helper = require('spec.spec_helper')
  local logged_messages = {}

  before_each(function()
    logged_messages = {}
    local mock_logger = {
      log = function(msg, level)
        table.insert(logged_messages, { msg = msg, level = level })
      end,
      set_config = function() end,
    }
    package.loaded['cp.log'] = mock_logger

    spec_helper.mock_async_scraper_success()

    local mock_async = {
      start_contest_operation = function() end,
      finish_contest_operation = function() end,
      get_active_operation = function()
        return nil
      end,
    }

    local mock_state = {
      get_platform = function()
        return 'atcoder'
      end,
      get_contest_id = function()
        return 'abc123'
      end,
      set_platform = function() end,
      set_contest_id = function() end,
      set_problem_id = function() end,
      set_test_cases = function() end,
      set_run_panel_active = function() end,
    }

    local mock_config = {
      setup = function()
        return {}
      end,
      get_config = function()
        return {
          scrapers = { 'atcoder', 'codeforces' },
          hooks = nil,
        }
      end,
    }

    local mock_cache = {
      load = function() end,
      get_contest_data = function()
        return nil
      end,
      get_test_cases = function()
        return nil
      end,
      set_file_state = function() end,
    }

    local mock_problem = {
      create_context = function()
        return {
          source_file = '/test/source.cpp',
          problem_name = 'abc123a',
        }
      end,
    }

    local mock_setup = {
      set_platform = function()
        return true
      end,
    }

    vim.cmd = {
      e = function() end,
      only = function() end,
    }
    vim.api.nvim_get_current_buf = function()
      return 1
    end
    vim.api.nvim_buf_get_lines = function()
      return { '' }
    end
    vim.fn.expand = function()
      return '/test/file.cpp'
    end

    package.loaded['cp.async'] = mock_async
    package.loaded['cp.state'] = mock_state
    package.loaded['cp.config'] = mock_config
    package.loaded['cp.cache'] = mock_cache
    package.loaded['cp.problem'] = mock_problem
    package.loaded['cp.setup'] = mock_setup

    cp = spec_helper.fresh_require('cp')
    cp.setup({})
  end)

  after_each(function()
    spec_helper.teardown()
    logged_messages = {}
  end)

  describe('command routing', function()
    it('contest_setup command uses async setup', function()
      local opts = { fargs = { 'atcoder', 'abc123' } }

      assert.has_no_errors(function()
        cp.handle_command(opts)
      end)
    end)

    it('full_setup command uses async setup', function()
      local opts = { fargs = { 'atcoder', 'abc123', 'a' } }

      assert.has_no_errors(function()
        cp.handle_command(opts)
      end)
    end)

    it('problem_switch uses async setup', function()
      local mock_state = require('cp.state')
      mock_state.get_contest_id = function()
        return 'abc123'
      end

      local opts = { fargs = { 'a' } }

      assert.has_no_errors(function()
        cp.handle_command(opts)
      end)
    end)
  end)

  describe('end-to-end workflow', function()
    it('handles complete contest setup workflow', function()
      local setup_completed = false
      local mock_async_setup = {
        setup_contest_async = function(contest_id)
          assert.equals('abc123', contest_id)
          setup_completed = true
        end,
      }
      package.loaded['cp.async.setup'] = mock_async_setup

      local opts = { fargs = { 'atcoder', 'abc123' } }
      cp.handle_command(opts)

      assert.is_true(setup_completed)
    end)

    it('handles problem switching within contest', function()
      local mock_state = require('cp.state')
      mock_state.get_contest_id = function()
        return 'abc123'
      end

      local problem_setup_called = false
      local mock_async_setup = {
        setup_problem_async = function(contest_id, problem_id, _)
          assert.equals('abc123', contest_id)
          assert.equals('b', problem_id)
          problem_setup_called = true
        end,
      }
      package.loaded['cp.async.setup'] = mock_async_setup

      local opts = { fargs = { 'b' } }
      cp.handle_command(opts)

      assert.is_true(problem_setup_called)
    end)

    it('handles language flags correctly', function()
      local language_passed = nil
      local mock_async_setup = {
        setup_contest_async = function(contest_id, language)
          language_passed = language
        end,
      }
      package.loaded['cp.async.setup'] = mock_async_setup

      local opts = { fargs = { 'atcoder', 'abc123', '--lang=python' } }
      cp.handle_command(opts)

      assert.equals('python', language_passed)
    end)

    it('handles scraping failures gracefully', function()
      spec_helper.mock_async_scraper_failure()

      local opts = { fargs = { 'atcoder', 'abc123' } }

      assert.has_no_errors(function()
        cp.handle_command(opts)
      end)
    end)
  end)

  describe('error handling', function()
    it('handles invalid platform gracefully', function()
      local opts = { fargs = { 'invalid_platform', 'abc123' } }

      cp.handle_command(opts)

      local error_logged = false
      for _, log_entry in ipairs(logged_messages) do
        if log_entry.level == vim.log.levels.ERROR then
          error_logged = true
          break
        end
      end
      assert.is_true(error_logged)
    end)

    it('handles platform setup failure', function()
      local mock_setup = require('cp.setup')
      mock_setup.set_platform = function()
        return false
      end

      local opts = { fargs = { 'atcoder', 'abc123' } }

      assert.has_no_errors(function()
        cp.handle_command(opts)
      end)
    end)

    it('handles empty contest context for problem switch', function()
      local mock_state = require('cp.state')
      mock_state.get_contest_id = function()
        return nil
      end

      local opts = { fargs = { 'a' } }

      cp.handle_command(opts)

      local error_logged = false
      for _, log_entry in ipairs(logged_messages) do
        if log_entry.level == vim.log.levels.ERROR then
          error_logged = true
          break
        end
      end
      assert.is_true(error_logged)
    end)
  end)

  describe('callback behavior', function()
    it('maintains execution context in callbacks', function()
      local callback_executed = false

      local mock_scraper = {
        scrape_contest_metadata_async = function(_, _, callback)
          vim.schedule(function()
            callback({ success = true, problems = { { id = 'a' } } })
            callback_executed = true
          end)
        end,
      }
      package.loaded['cp.async.scraper'] = mock_scraper

      local opts = { fargs = { 'atcoder', 'abc123' } }
      cp.handle_command(opts)

      assert.is_true(callback_executed)
    end)

    it('handles multiple rapid commands', function()
      local command_count = 0
      local mock_async_setup = {
        setup_contest_async = function()
          command_count = command_count + 1
        end,
      }
      package.loaded['cp.async.setup'] = mock_async_setup

      cp.handle_command({ fargs = { 'atcoder', 'abc123' } })
      cp.handle_command({ fargs = { 'atcoder', 'abc124' } })
      cp.handle_command({ fargs = { 'atcoder', 'abc125' } })

      assert.equals(3, command_count)
    end)
  end)
end)
