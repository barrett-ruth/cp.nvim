describe('cp.scrape', function()
  local scrape
  local mock_cache
  local mock_system_calls
  local temp_files
  local spec_helper = require('spec.spec_helper')

  before_each(function()
    spec_helper.setup()
    temp_files = {}

    mock_cache = {
      load = function() end,
      get_contest_data = function()
        return nil
      end,
      set_contest_data = function() end,
      set_test_cases = function() end,
    }

    mock_system_calls = {}

    vim.system = function(cmd, opts)
      table.insert(mock_system_calls, { cmd = cmd, opts = opts })

      local result = { code = 0, stdout = '{}', stderr = '' }

      if cmd[1] == 'ping' then
        result = { code = 0 }
      elseif cmd[1] == 'uv' and cmd[2] == 'sync' then
        result = { code = 0, stdout = '', stderr = '' }
      elseif cmd[1] == 'uv' and cmd[2] == 'run' then
        if vim.tbl_contains(cmd, 'metadata') then
          result.stdout = '{"success": true, "problems": [{"id": "a", "name": "Test Problem"}]}'
        elseif vim.tbl_contains(cmd, 'tests') then
          result.stdout =
            '{"success": true, "tests": [{"input": "1 2", "expected": "3"}], "url": "https://example.com", "timeout_ms": 2000, "memory_mb": 256.0}'
        end
      end

      return {
        wait = function()
          return result
        end,
      }
    end

    package.loaded['cp.cache'] = mock_cache
    scrape = require('cp.scrape')

    local original_fn = vim.fn
    vim.fn = vim.tbl_extend('force', vim.fn, {
      executable = function(cmd)
        if cmd == 'uv' then
          return 1
        end
        return original_fn.executable(cmd)
      end,
      isdirectory = function(path)
        if path:match('%.venv$') then
          return 1
        end
        return original_fn.isdirectory(path)
      end,
      filereadable = function(path)
        if temp_files[path] then
          return 1
        end
        return 0
      end,
      readfile = function(path)
        return temp_files[path] or {}
      end,
      writefile = function(lines, path)
        temp_files[path] = lines
      end,
      mkdir = function() end,
      fnamemodify = function(path, modifier)
        if modifier == ':r' then
          return path:gsub('%..*$', '')
        end
        return original_fn.fnamemodify(path, modifier)
      end,
    })
  end)

  after_each(function()
    package.loaded['cp.cache'] = nil
    vim.system = vim.system_original or vim.system
    spec_helper.teardown()
    temp_files = {}
  end)

  describe('cache integration', function()
    it('returns cached data when available', function()
      mock_cache.get_contest_data = function(platform, contest_id)
        if platform == 'atcoder' and contest_id == 'abc123' then
          return { problems = { { id = 'a', name = 'Cached Problem' } } }
        end
        return nil
      end

      local result = scrape.scrape_contest_metadata('atcoder', 'abc123')

      assert.is_true(result.success)
      assert.equals(1, #result.problems)
      assert.equals('Cached Problem', result.problems[1].name)
      assert.equals(0, #mock_system_calls)
    end)

    it('stores scraped data in cache after successful scrape', function()
      local stored_data = nil
      mock_cache.set_contest_data = function(platform, contest_id, problems)
        stored_data = { platform = platform, contest_id = contest_id, problems = problems }
      end

      package.loaded['cp.scrape'] = nil
      scrape = require('cp.scrape')

      local result = scrape.scrape_contest_metadata('atcoder', 'abc123')

      assert.is_true(result.success)
      assert.is_not_nil(stored_data)
      assert.equals('atcoder', stored_data.platform)
      assert.equals('abc123', stored_data.contest_id)
      assert.equals(1, #stored_data.problems)
    end)
  end)

  describe('system dependency checks', function()
    it('handles missing uv executable', function()
      vim.fn.executable = function(cmd)
        return cmd == 'uv' and 0 or 1
      end

      local result = scrape.scrape_contest_metadata('atcoder', 'abc123')

      assert.is_false(result.success)
      assert.is_not_nil(result.error:match('Python environment setup failed'))
    end)

    it('handles python environment setup failure', function()
      vim.system = function(cmd)
        if cmd[1] == 'ping' then
          return {
            wait = function()
              return { code = 0 }
            end,
          }
        elseif cmd[1] == 'uv' and cmd[2] == 'sync' then
          return {
            wait = function()
              return { code = 1, stderr = 'setup failed' }
            end,
          }
        end
        return {
          wait = function()
            return { code = 0 }
          end,
        }
      end

      vim.fn.isdirectory = function()
        return 0
      end

      local result = scrape.scrape_contest_metadata('atcoder', 'abc123')

      assert.is_false(result.success)
      assert.is_not_nil(result.error:match('Python environment setup failed'))
    end)

    it('handles network connectivity issues', function()
      vim.system = function(cmd)
        if cmd[1] == 'ping' then
          return {
            wait = function()
              return { code = 1 }
            end,
          }
        end
        return {
          wait = function()
            return { code = 0 }
          end,
        }
      end

      local result = scrape.scrape_contest_metadata('atcoder', 'abc123')

      assert.is_false(result.success)
      assert.equals('No internet connection available', result.error)
    end)
  end)

  describe('subprocess execution', function()
    it('constructs correct command for atcoder metadata', function()
      scrape.scrape_contest_metadata('atcoder', 'abc123')

      local metadata_call = nil
      for _, call in ipairs(mock_system_calls) do
        if vim.tbl_contains(call.cmd, 'metadata') then
          metadata_call = call
          break
        end
      end

      assert.is_not_nil(metadata_call)
      assert.equals('uv', metadata_call.cmd[1])
      assert.equals('run', metadata_call.cmd[2])
      assert.is_true(vim.tbl_contains(metadata_call.cmd, 'metadata'))
      assert.is_true(vim.tbl_contains(metadata_call.cmd, 'abc123'))
    end)

    it('constructs correct command for cses metadata', function()
      scrape.scrape_contest_metadata('cses', 'problemset')

      local metadata_call = nil
      for _, call in ipairs(mock_system_calls) do
        if vim.tbl_contains(call.cmd, 'metadata') then
          metadata_call = call
          break
        end
      end

      assert.is_not_nil(metadata_call)
      assert.equals('uv', metadata_call.cmd[1])
      assert.is_true(vim.tbl_contains(metadata_call.cmd, 'metadata'))
      assert.is_false(vim.tbl_contains(metadata_call.cmd, 'problemset'))
    end)

    it('handles subprocess execution failure', function()
      vim.system = function(cmd)
        if cmd[1] == 'ping' then
          return {
            wait = function()
              return { code = 0 }
            end,
          }
        elseif cmd[1] == 'uv' and vim.tbl_contains(cmd, 'metadata') then
          return {
            wait = function()
              return { code = 1, stderr = 'execution failed' }
            end,
          }
        end
        return {
          wait = function()
            return { code = 0 }
          end,
        }
      end

      local result = scrape.scrape_contest_metadata('atcoder', 'abc123')

      assert.is_false(result.success)
      assert.is_not_nil(result.error:match('Failed to run metadata scraper'))
      assert.is_not_nil(result.error:match('execution failed'))
    end)
  end)

  describe('json parsing', function()
    it('handles invalid json output', function()
      vim.system = function(cmd)
        if cmd[1] == 'ping' then
          return {
            wait = function()
              return { code = 0 }
            end,
          }
        elseif cmd[1] == 'uv' and vim.tbl_contains(cmd, 'metadata') then
          return {
            wait = function()
              return { code = 0, stdout = 'invalid json' }
            end,
          }
        end
        return {
          wait = function()
            return { code = 0 }
          end,
        }
      end

      local result = scrape.scrape_contest_metadata('atcoder', 'abc123')

      assert.is_false(result.success)
      assert.is_not_nil(result.error:match('Failed to parse metadata scraper output'))
    end)

    it('handles scraper-reported failures', function()
      vim.system = function(cmd)
        if cmd[1] == 'ping' then
          return {
            wait = function()
              return { code = 0 }
            end,
          }
        elseif cmd[1] == 'uv' and vim.tbl_contains(cmd, 'metadata') then
          return {
            wait = function()
              return {
                code = 0,
                stdout = '{"success": false, "error": "contest not found"}',
              }
            end,
          }
        end
        return {
          wait = function()
            return { code = 0 }
          end,
        }
      end

      local result = scrape.scrape_contest_metadata('atcoder', 'abc123')

      assert.is_false(result.success)
      assert.equals('contest not found', result.error)
    end)
  end)

  describe('problem scraping', function()
    local test_context

    before_each(function()
      test_context = {
        contest = 'atcoder',
        contest_id = 'abc123',
        problem_id = 'a',
        problem_name = 'abc123a',
        input_file = 'io/abc123a.cpin',
        expected_file = 'io/abc123a.expected',
      }
    end)

    it('uses existing files when available', function()
      temp_files['io/abc123a.cpin'] = { '1 2' }
      temp_files['io/abc123a.expected'] = { '3' }
      temp_files['io/abc123a.1.cpin'] = { '4 5' }
      temp_files['io/abc123a.1.cpout'] = { '9' }

      local result = scrape.scrape_problem(test_context)

      assert.is_true(result.success)
      assert.equals('abc123a', result.problem_id)
      assert.equals(1, result.test_count)
      assert.equals(0, #mock_system_calls)
    end)

    it('scrapes and writes test case files', function()
      local result = scrape.scrape_problem(test_context)

      assert.is_true(result.success)
      assert.equals('abc123a', result.problem_id)
      assert.equals(1, result.test_count)
      assert.is_not_nil(temp_files['io/abc123a.1.cpin'])
      assert.is_not_nil(temp_files['io/abc123a.1.cpout'])
      assert.equals('1 2', table.concat(temp_files['io/abc123a.1.cpin'], '\n'))
      assert.equals('3', table.concat(temp_files['io/abc123a.1.cpout'], '\n'))
    end)

    it('constructs correct command for atcoder problem tests', function()
      scrape.scrape_problem(test_context)

      local tests_call = nil
      for _, call in ipairs(mock_system_calls) do
        if vim.tbl_contains(call.cmd, 'tests') then
          tests_call = call
          break
        end
      end

      assert.is_not_nil(tests_call)
      assert.is_true(vim.tbl_contains(tests_call.cmd, 'tests'))
      assert.is_true(vim.tbl_contains(tests_call.cmd, 'abc123'))
      assert.is_true(vim.tbl_contains(tests_call.cmd, 'a'))
    end)

    it('constructs correct command for cses problem tests', function()
      test_context.contest = 'cses'
      test_context.contest_id = '1001'
      test_context.problem_id = nil

      scrape.scrape_problem(test_context)

      local tests_call = nil
      for _, call in ipairs(mock_system_calls) do
        if vim.tbl_contains(call.cmd, 'tests') then
          tests_call = call
          break
        end
      end

      assert.is_not_nil(tests_call)
      assert.is_true(vim.tbl_contains(tests_call.cmd, 'tests'))
      assert.is_true(vim.tbl_contains(tests_call.cmd, '1001'))
      assert.is_false(vim.tbl_contains(tests_call.cmd, 'a'))
    end)
  end)

  describe('error scenarios', function()
    it('validates input parameters', function()
      assert.has_error(function()
        scrape.scrape_contest_metadata(nil, 'abc123')
      end)

      assert.has_error(function()
        scrape.scrape_contest_metadata('atcoder', nil)
      end)
    end)

    it('handles file system errors gracefully', function()
      vim.fn.mkdir = function()
        error('permission denied')
      end

      local ctx = {
        contest = 'atcoder',
        contest_id = 'abc123',
        problem_id = 'a',
        problem_name = 'abc123a',
        input_file = 'io/abc123a.cpin',
        expected_file = 'io/abc123a.expected',
      }

      assert.has_error(function()
        scrape.scrape_problem(ctx)
      end)
    end)
  end)
end)
