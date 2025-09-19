describe('cp.scrape', function()
  local scrape

  local function setup_mocks()
    package.loaded['cp.log'] = { log = function() end, set_config = function() end }
    package.loaded['cp.cache'] = {
      load = function() end,
      get_contest_data = function()
        return nil
      end,
      set_contest_data = function() end,
    }
  end

  local function mock_success()
    vim.system = function(cmd)
      if cmd[1] == 'ping' then
        return {
          wait = function()
            return { code = 0 }
          end,
        }
      end
      if cmd[1] == 'uv' and cmd[2] == 'sync' then
        return {
          wait = function()
            return { code = 0 }
          end,
        }
      end
      if cmd[1] == 'uv' and cmd[2] == 'run' then
        local response = vim.tbl_contains(cmd, 'metadata')
            and '{"success": true, "problems": [{"id": "a", "name": "Problem A"}]}'
          or '{"success": true, "tests": [{"input": "1", "expected": "1"}]}'
        return {
          wait = function()
            return { code = 0, stdout = response }
          end,
        }
      end
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end
  end

  local function mock_failure(fail_type, error_msg)
    vim.system = function(cmd)
      if fail_type == 'ping' and cmd[1] == 'ping' then
        return {
          wait = function()
            return { code = 1 }
          end,
        }
      elseif fail_type == 'uv_sync' and cmd[1] == 'uv' and cmd[2] == 'sync' then
        return {
          wait = function()
            return { code = 1, stderr = error_msg }
          end,
        }
      elseif fail_type == 'scraper' and cmd[1] == 'uv' and cmd[2] == 'run' then
        return {
          wait = function()
            return { code = 1, stderr = error_msg }
          end,
        }
      end
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end
  end

  before_each(function()
    setup_mocks()
    vim.fn = vim.tbl_extend('force', vim.fn or {}, {
      executable = function()
        return 1
      end,
      isdirectory = function()
        return 1
      end,
      filereadable = function()
        return 0
      end,
      readfile = function()
        return {}
      end,
      writefile = function() end,
      mkdir = function() end,
      fnamemodify = function()
        return '/test/path'
      end,
    })
    scrape = require('cp.scrape')
  end)

  after_each(function()
    package.loaded['cp.cache'] = nil
    package.loaded['cp.log'] = nil
  end)

  describe('cache integration', function()
    it('returns cached data when available', function()
      package.loaded['cp.cache'].get_contest_data = function()
        return { problems = { { id = 'a', name = 'Problem A' } } }
      end

      local result = scrape.scrape_contest_metadata('atcoder', 'abc123')

      assert.is_true(result.success)
      assert.equals(1, #result.problems)
    end)

    it('stores scraped data in cache after successful scrape', function()
      local stored_data = nil
      package.loaded['cp.cache'].set_contest_data = function(platform, contest_id, data)
        stored_data = { platform = platform, contest_id = contest_id, problems = data }
      end
      mock_success()

      scrape.scrape_contest_metadata('atcoder', 'abc123')

      assert.is_not_nil(stored_data)
      assert.equals('atcoder', stored_data.platform)
      assert.equals('abc123', stored_data.contest_id)
    end)
  end)

  describe('system dependency checks', function()
    it('handles missing uv executable', function()
      vim.fn.executable = function()
        return 0
      end

      local result = scrape.scrape_contest_metadata('atcoder', 'abc123')

      assert.is_false(result.success)
      assert.is_not_nil(result.error:match('Python environment setup failed'))
    end)

    it('handles python environment setup failure', function()
      vim.fn.isdirectory = function()
        return 0
      end
      mock_failure('uv_sync', 'setup failed')

      local result = scrape.scrape_contest_metadata('atcoder', 'abc123')

      assert.is_false(result.success)
      assert.is_not_nil(result.error:match('Python environment setup failed'))
    end)

    it('handles network connectivity issues', function()
      mock_failure('ping', '')

      local result = scrape.scrape_contest_metadata('atcoder', 'abc123')

      assert.is_false(result.success)
      assert.equals('No internet connection available', result.error)
    end)
  end)

  describe('subprocess execution', function()
    it('constructs correct command for atcoder metadata', function()
      local captured_cmd = nil
      vim.system = function(cmd)
        captured_cmd = cmd
        return {
          wait = function()
            return { code = 0, stdout = '{"success": true, "problems": []}' }
          end,
        }
      end

      scrape.scrape_contest_metadata('atcoder', 'abc123')

      assert.is_not_nil(captured_cmd)
      assert.equals('uv', captured_cmd[1])
      assert.is_true(vim.tbl_contains(captured_cmd, 'metadata'))
      assert.is_true(vim.tbl_contains(captured_cmd, 'abc123'))
    end)

    it('constructs correct command for cses metadata', function()
      local captured_cmd = nil
      vim.system = function(cmd)
        captured_cmd = cmd
        return {
          wait = function()
            return { code = 0, stdout = '{"success": true, "problems": []}' }
          end,
        }
      end

      scrape.scrape_contest_metadata('cses', '')

      assert.is_not_nil(captured_cmd)
      assert.equals('uv', captured_cmd[1])
      assert.is_true(vim.tbl_contains(captured_cmd, 'metadata'))
      assert.is_false(vim.tbl_contains(captured_cmd, ''))
    end)

    it('handles subprocess execution failure', function()
      mock_failure('scraper', 'network error')

      local result = scrape.scrape_contest_metadata('atcoder', 'abc123')

      assert.is_false(result.success)
      assert.is_not_nil(result.error:match('Failed to run metadata scraper'))
    end)
  end)

  describe('json parsing', function()
    it('handles invalid json output', function()
      vim.system = function()
        return {
          wait = function()
            return { code = 0, stdout = 'invalid json' }
          end,
        }
      end

      local result = scrape.scrape_contest_metadata('atcoder', 'abc123')

      assert.is_false(result.success)
      assert.is_not_nil(result.error:match('Failed to parse metadata scraper output'))
    end)

    it('handles scraper-reported failures', function()
      vim.system = function()
        return {
          wait = function()
            return { code = 0, stdout = '{"success": false, "error": "scraper error"}' }
          end,
        }
      end

      local result = scrape.scrape_contest_metadata('atcoder', 'abc123')

      assert.is_false(result.success)
    end)
  end)

  describe('problem scraping', function()
    it('uses existing files when available', function()
      vim.fn.filereadable = function()
        return 1
      end
      vim.fn.readfile = function()
        return { 'test input' }
      end

      local result = scrape.scrape_problem({
        contest = 'atcoder',
        contest_id = 'abc123',
        problem_id = 'a',
        input_file = 'test.cpin',
        expected_file = 'test.cpout',
        problem_name = 'test',
      })

      assert.is_true(result.success)
    end)

    it('scrapes and writes test case files', function()
      local written_files = {}
      vim.fn.writefile = function(lines, path)
        written_files[path] = lines
      end
      mock_success()

      scrape.scrape_problem({
        contest = 'atcoder',
        contest_id = 'abc123',
        problem_id = 'a',
        input_file = 'test.cpin',
        expected_file = 'test.cpout',
        problem_name = 'test',
      })

      assert.is_not_nil(next(written_files))
    end)

    it('constructs correct command for atcoder problem tests', function()
      local captured_cmd = nil
      vim.system = function(cmd)
        if cmd[1] == 'uv' and cmd[2] == 'run' then
          captured_cmd = cmd
        end
        return {
          wait = function()
            return { code = 0, stdout = '{"success": true, "tests": []}' }
          end,
        }
      end

      scrape.scrape_problem({
        contest = 'atcoder',
        contest_id = 'abc123',
        problem_id = 'a',
        problem_name = 'test',
      })

      assert.is_not_nil(captured_cmd)
      assert.is_true(vim.tbl_contains(captured_cmd, 'tests'))
      assert.is_true(vim.tbl_contains(captured_cmd, 'abc123'))
      assert.is_true(vim.tbl_contains(captured_cmd, 'a'))
    end)

    it('constructs correct command for cses problem tests', function()
      local captured_cmd = nil
      vim.system = function(cmd)
        if cmd[1] == 'uv' and cmd[2] == 'run' then
          captured_cmd = cmd
        end
        return {
          wait = function()
            return { code = 0, stdout = '{"success": true, "tests": []}' }
          end,
        }
      end

      scrape.scrape_problem({
        contest = 'cses',
        contest_id = '1234',
        problem_name = 'test',
      })

      assert.is_not_nil(captured_cmd)
      assert.is_true(vim.tbl_contains(captured_cmd, 'tests'))
      assert.is_true(vim.tbl_contains(captured_cmd, '1234'))
    end)
  end)

  describe('error scenarios', function()
    it('validates input parameters', function()
      assert.has_error(function()
        scrape.scrape_contest_metadata()
      end)

      assert.has_error(function()
        scrape.scrape_problem()
      end)
    end)

    it('handles file system errors gracefully', function()
      vim.fn.writefile = function()
        error('permission denied')
      end
      mock_success()

      assert.has_no_errors(function()
        scrape.scrape_problem({
          contest = 'atcoder',
          contest_id = 'abc123',
          problem_id = 'a',
          problem_name = 'test',
        })
      end)
    end)
  end)
end)
