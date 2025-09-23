describe('cp.async.setup', function()
  local setup
  local spec_helper = require('spec.spec_helper')
  local mock_async, mock_scraper, mock_state
  before_each(function()
    spec_helper.setup()

    mock_async = {
      start_contest_operation = function() end,
      finish_contest_operation = function() end,
    }

    mock_scraper = {
      scrape_contest_metadata_async = function(_, _, callback)
        callback({
          success = true,
          problems = {
            { id = 'a', name = 'Problem A' },
            { id = 'b', name = 'Problem B' },
          },
        })
      end,
      scrape_problem_async = function(_, _, problem_id, callback)
        callback({
          success = true,
          problem_id = problem_id,
          test_cases = { { input = '1', expected = '1' } },
          test_count = 1,
        })
      end,
    }

    mock_state = {
      get_platform = function()
        return 'atcoder'
      end,
      get_contest_id = function()
        return 'abc123'
      end,
      set_contest_id = function() end,
      set_problem_id = function() end,
      set_test_cases = function() end,
      set_run_panel_active = function() end,
    }

    local mock_config = {
      get_config = function()
        return {
          scrapers = { 'atcoder', 'codeforces' },
          hooks = nil,
        }
      end,
    }

    local mock_cache = {
      load = function() end,
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

    vim.cmd = function() end
    vim.cmd.e = function() end
    vim.cmd.only = function() end
    vim.cmd.startinsert = function() end
    vim.cmd.stopinsert = function() end
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
    package.loaded['cp.async.scraper'] = mock_scraper
    package.loaded['cp.state'] = mock_state
    package.loaded['cp.config'] = mock_config
    package.loaded['cp.cache'] = mock_cache
    package.loaded['cp.problem'] = mock_problem

    setup = spec_helper.fresh_require('cp.async.setup')
  end)

  after_each(function()
    spec_helper.teardown()
  end)

  describe('setup_contest_async', function()
    it('guards against multiple simultaneous operations', function()
      local started = false
      mock_async.start_contest_operation = function()
        started = true
      end

      setup.setup_contest_async('abc123', 'cpp')

      assert.is_true(started)
    end)

    it('handles metadata scraping success', function()
      local finished = false
      mock_async.finish_contest_operation = function()
        finished = true
      end

      setup.setup_contest_async('abc123', 'cpp')

      assert.is_true(finished)
    end)

    it('handles metadata scraping failure gracefully', function()
      mock_scraper.scrape_contest_metadata_async = function(_, _, callback)
        callback({
          success = false,
          error = 'network error',
        })
      end

      local finished = false
      mock_async.finish_contest_operation = function()
        finished = true
      end

      setup.setup_contest_async('abc123', 'cpp')

      assert.is_true(finished)
    end)

    it('handles disabled scraping platform', function()
      mock_state.get_platform = function()
        return 'disabled_platform'
      end

      assert.has_no_errors(function()
        setup.setup_contest_async('abc123', 'cpp')
      end)
    end)
  end)

  describe('setup_problem_async', function()
    it('opens buffer immediately', function()
      local buffer_opened = false
      vim.cmd.e = function()
        buffer_opened = true
      end

      setup.setup_problem_async('abc123', 'a', 'cpp')

      assert.is_true(buffer_opened)
    end)

    it('uses cached test cases if available', function()
      local cached_cases = { { input = 'cached', expected = 'result' } }
      local mock_cache = require('cp.cache')
      mock_cache.get_test_cases = function()
        return cached_cases
      end

      local set_test_cases_called = false
      mock_state.set_test_cases = function(cases)
        assert.same(cached_cases, cases)
        set_test_cases_called = true
      end

      setup.setup_problem_async('abc123', 'a', 'cpp')

      assert.is_true(set_test_cases_called)
    end)

    it('starts background test scraping if not cached', function()
      local scraping_started = false
      mock_scraper.scrape_problem_async = function(_, _, problem_id, callback)
        scraping_started = true
        callback({ success = true, problem_id = problem_id, test_cases = {} })
      end

      setup.setup_problem_async('abc123', 'a', 'cpp')

      assert.is_true(scraping_started)
    end)

    it('finishes contest operation on completion', function()
      local finished = false
      mock_async.finish_contest_operation = function()
        finished = true
      end

      setup.setup_problem_async('abc123', 'a', 'cpp')

      assert.is_true(finished)
    end)
  end)

  describe('handle_full_setup_async', function()
    it('validates problem exists in contest', function()
      mock_scraper.scrape_contest_metadata_async = function(_, _, callback)
        callback({
          success = true,
          problems = { { id = 'a' }, { id = 'b' } },
        })
      end

      local cmd = { platform = 'atcoder', contest = 'abc123', problem = 'c' }

      local finished = false
      mock_async.finish_contest_operation = function()
        finished = true
      end

      setup.handle_full_setup_async(cmd)

      assert.is_true(finished)
    end)

    it('proceeds with valid problem', function()
      mock_scraper.scrape_contest_metadata_async = function(_, _, callback)
        callback({
          success = true,
          problems = { { id = 'a' }, { id = 'b' } },
        })
      end

      local cmd = { platform = 'atcoder', contest = 'abc123', problem = 'a' }

      assert.has_no_errors(function()
        setup.handle_full_setup_async(cmd)
      end)
    end)
  end)

  describe('background problem scraping', function()
    it('scrapes uncached problems in background', function()
      local problems = { { id = 'a' }, { id = 'b' }, { id = 'c' } }
      local scraping_calls = {}

      mock_scraper.scrape_problem_async = function(_, _, problem_id, callback)
        scraping_calls[#scraping_calls + 1] = problem_id
        callback({ success = true, problem_id = problem_id })
      end

      local mock_cache = require('cp.cache')
      mock_cache.get_test_cases = function()
        return nil
      end

      setup.start_background_problem_scraping('abc123', problems, { scrapers = { 'atcoder' } })

      assert.equals(3, #scraping_calls)
      assert.is_true(vim.tbl_contains(scraping_calls, 'a'))
      assert.is_true(vim.tbl_contains(scraping_calls, 'b'))
      assert.is_true(vim.tbl_contains(scraping_calls, 'c'))
    end)

    it('skips already cached problems', function()
      local problems = { { id = 'a' }, { id = 'b' } }
      local scraping_calls = {}

      mock_scraper.scrape_problem_async = function(_, _, problem_id, callback)
        scraping_calls[#scraping_calls + 1] = problem_id
        callback({ success = true, problem_id = problem_id })
      end

      local mock_cache = require('cp.cache')
      mock_cache.get_test_cases = function(_, _, problem_id)
        return problem_id == 'a' and { { input = '1', expected = '1' } } or nil
      end

      setup.start_background_problem_scraping('abc123', problems, { scrapers = { 'atcoder' } })

      assert.equals(1, #scraping_calls)
      assert.equals('b', scraping_calls[1])
    end)
  end)
end)
