describe('cp.async.scraper', function()
  local scraper
  local spec_helper = require('spec.spec_helper')
  local mock_cache, mock_utils
  local callback_results = {}

  before_each(function()
    spec_helper.setup()
    callback_results = {}

    mock_cache = {
      load = function() end,
      get_contest_data = function()
        return nil
      end,
      set_contest_data = function() end,
      set_test_cases = function() end,
    }

    mock_utils = {
      setup_python_env = function()
        return true
      end,
      get_plugin_path = function()
        return '/test/plugin'
      end,
    }

    vim.system = function(cmd, _, callback)
      local result = { code = 0, stdout = '{}', stderr = '' }
      if cmd[1] == 'ping' then
        result = { code = 0 }
      elseif cmd[1] == 'uv' and vim.tbl_contains(cmd, 'metadata') then
        result.stdout = '{"success": true, "problems": [{"id": "a", "name": "Test Problem"}]}'
      elseif cmd[1] == 'uv' and vim.tbl_contains(cmd, 'tests') then
        result.stdout =
          '{"success": true, "tests": [{"input": "1 2", "expected": "3"}], "timeout_ms": 2000, "memory_mb": 256.0, "url": "https://example.com"}'
      end
      callback(result)
    end

    vim.fn.mkdir = function() end

    package.loaded['cp.cache'] = mock_cache
    package.loaded['cp.utils'] = mock_utils
    scraper = spec_helper.fresh_require('cp.async.scraper')
  end)

  after_each(function()
    spec_helper.teardown()
  end)

  describe('scrape_contest_metadata_async', function()
    it('returns cached data immediately if available', function()
      mock_cache.get_contest_data = function()
        return { problems = { { id = 'cached', name = 'Cached Problem' } } }
      end

      scraper.scrape_contest_metadata_async('atcoder', 'abc123', function(result)
        callback_results[#callback_results + 1] = result
      end)

      assert.equals(1, #callback_results)
      assert.is_true(callback_results[1].success)
      assert.equals('Cached Problem', callback_results[1].problems[1].name)
    end)

    it('calls callback with success result after scraping', function()
      scraper.scrape_contest_metadata_async('atcoder', 'abc123', function(result)
        callback_results[#callback_results + 1] = result
      end)

      assert.equals(1, #callback_results)
      assert.is_true(callback_results[1].success)
      assert.equals(1, #callback_results[1].problems)
      assert.equals('Test Problem', callback_results[1].problems[1].name)
    end)

    it('calls callback with error on network failure', function()
      vim.system = function(cmd, _, callback)
        if cmd[1] == 'ping' then
          callback({ code = 1 })
        end
      end

      scraper.scrape_contest_metadata_async('atcoder', 'abc123', function(result)
        callback_results[#callback_results + 1] = result
      end)

      assert.equals(1, #callback_results)
      assert.is_false(callback_results[1].success)
      assert.equals('No internet connection available', callback_results[1].error)
    end)

    it('calls callback with error on python env failure', function()
      mock_utils.setup_python_env = function()
        return false
      end

      scraper.scrape_contest_metadata_async('atcoder', 'abc123', function(result)
        callback_results[#callback_results + 1] = result
      end)

      assert.equals(1, #callback_results)
      assert.is_false(callback_results[1].success)
      assert.equals('Python environment setup failed', callback_results[1].error)
    end)

    it('calls callback with error on subprocess failure', function()
      vim.system = function(cmd, _, callback)
        if cmd[1] == 'ping' then
          callback({ code = 0 })
        else
          callback({ code = 1, stderr = 'execution failed' })
        end
      end

      scraper.scrape_contest_metadata_async('atcoder', 'abc123', function(result)
        callback_results[#callback_results + 1] = result
      end)

      assert.equals(1, #callback_results)
      assert.is_false(callback_results[1].success)
      assert.is_not_nil(callback_results[1].error:match('Failed to run metadata scraper'))
    end)

    it('calls callback with error on invalid JSON', function()
      vim.system = function(cmd, _, callback)
        if cmd[1] == 'ping' then
          callback({ code = 0 })
        else
          callback({ code = 0, stdout = 'invalid json' })
        end
      end

      scraper.scrape_contest_metadata_async('atcoder', 'abc123', function(result)
        callback_results[#callback_results + 1] = result
      end)

      assert.equals(1, #callback_results)
      assert.is_false(callback_results[1].success)
      assert.is_not_nil(callback_results[1].error:match('Failed to parse metadata scraper output'))
    end)
  end)

  describe('scrape_problem_async', function()
    it('calls callback with success after scraping tests', function()
      scraper.scrape_problem_async('atcoder', 'abc123', 'a', function(result)
        callback_results[#callback_results + 1] = result
      end)

      assert.equals(1, #callback_results)
      assert.is_true(callback_results[1].success)
      assert.equals('a', callback_results[1].problem_id)
      assert.equals(1, callback_results[1].test_count)
    end)

    it('handles network failure gracefully', function()
      vim.system = function(cmd, _, callback)
        if cmd[1] == 'ping' then
          callback({ code = 1 })
        end
      end

      scraper.scrape_problem_async('atcoder', 'abc123', 'a', function(result)
        callback_results[#callback_results + 1] = result
      end)

      assert.equals(1, #callback_results)
      assert.is_false(callback_results[1].success)
      assert.equals('a', callback_results[1].problem_id)
      assert.equals('No internet connection available', callback_results[1].error)
    end)

    it('validates input parameters', function()
      assert.has_error(function()
        scraper.scrape_contest_metadata_async(nil, 'abc123', function() end)
      end)

      assert.has_error(function()
        scraper.scrape_problem_async('atcoder', nil, 'a', function() end)
      end)
    end)
  end)
end)
