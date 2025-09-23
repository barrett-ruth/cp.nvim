describe('cp.cache', function()
  local cache
  local spec_helper = require('spec.spec_helper')

  before_each(function()
    spec_helper.setup()

    local mock_file_content = '{}'
    vim.fn.filereadable = function()
      return 1
    end
    vim.fn.readfile = function()
      return { mock_file_content }
    end
    vim.fn.writefile = function(lines)
      mock_file_content = table.concat(lines, '\n')
    end
    vim.fn.mkdir = function() end

    cache = require('cp.cache')
    cache.load()
  end)

  after_each(function()
    spec_helper.teardown()
    cache.clear_contest_data('atcoder', 'test_contest')
    cache.clear_contest_data('codeforces', 'test_contest')
    cache.clear_contest_data('cses', 'test_contest')
  end)

  describe('load and save', function()
    it('loads without error when cache file exists', function()
      assert.has_no_errors(function()
        cache.load()
      end)
    end)

    it('saves and persists data', function()
      local problems = { { id = 'A', name = 'Problem A' } }

      assert.has_no_errors(function()
        cache.set_contest_data('atcoder', 'test_contest', problems)
      end)

      local result = cache.get_contest_data('atcoder', 'test_contest')
      assert.is_not_nil(result)
      assert.equals('A', result.problems[1].id)
    end)
  end)

  describe('contest data', function()
    it('stores and retrieves contest data', function()
      local problems = {
        { id = 'A', name = 'First Problem' },
        { id = 'B', name = 'Second Problem' },
      }

      cache.set_contest_data('codeforces', 'test_contest', problems)
      local result = cache.get_contest_data('codeforces', 'test_contest')

      assert.is_not_nil(result)
      assert.equals(2, #result.problems)
      assert.equals('A', result.problems[1].id)
      assert.equals('Second Problem', result.problems[2].name)
    end)

    it('returns nil for missing contest', function()
      local result = cache.get_contest_data('atcoder', 'nonexistent_contest')
      assert.is_nil(result)
    end)

    it('clears contest data', function()
      local problems = { { id = 'A' } }
      cache.set_contest_data('atcoder', 'test_contest', problems)

      cache.clear_contest_data('atcoder', 'test_contest')
      local result = cache.get_contest_data('atcoder', 'test_contest')

      assert.is_nil(result)
    end)

    it('handles cses expiry correctly', function()
      local problems = { { id = 'A' } }
      cache.set_contest_data('cses', 'test_contest', problems)

      local result = cache.get_contest_data('cses', 'test_contest')
      assert.is_not_nil(result)
      assert.is_not_nil(result.expires_at)
    end)
  end)

  describe('test cases', function()
    it('stores and retrieves test cases', function()
      local test_cases = {
        { index = 1, input = '1 2', expected = '3' },
        { index = 2, input = '4 5', expected = '9' },
      }

      cache.set_test_cases('atcoder', 'test_contest', 'A', test_cases)
      local result = cache.get_test_cases('atcoder', 'test_contest', 'A')

      assert.is_not_nil(result)
      assert.equals(2, #result)
      assert.equals('1 2', result[1].input)
      assert.equals('9', result[2].expected)
    end)

    it('handles contest-level test cases', function()
      local test_cases = { { input = 'test', expected = 'output' } }

      cache.set_test_cases('cses', 'test_contest', nil, test_cases)
      local result = cache.get_test_cases('cses', 'test_contest', nil)

      assert.is_not_nil(result)
      assert.equals(1, #result)
      assert.equals('test', result[1].input)
    end)

    it('returns nil for missing test cases', function()
      local result = cache.get_test_cases('atcoder', 'nonexistent', 'A')
      assert.is_nil(result)
    end)
  end)

  describe('file state', function()
    it('stores and retrieves file state', function()
      local file_path = '/tmp/test.cpp'

      cache.set_file_state(file_path, 'atcoder', 'abc123', 'a', 'cpp')
      local result = cache.get_file_state(file_path)

      assert.is_not_nil(result)
      assert.equals('atcoder', result.platform)
      assert.equals('abc123', result.contest_id)
      assert.equals('a', result.problem_id)
      assert.equals('cpp', result.language)
    end)

    it('handles cses file state without problem_id', function()
      local file_path = '/tmp/cses.py'

      cache.set_file_state(file_path, 'cses', '1068', nil, 'python')
      local result = cache.get_file_state(file_path)

      assert.is_not_nil(result)
      assert.equals('cses', result.platform)
      assert.equals('1068', result.contest_id)
      assert.is_nil(result.problem_id)
      assert.equals('python', result.language)
    end)

    it('returns nil for missing file state', function()
      local result = cache.get_file_state('/nonexistent/file.cpp')
      assert.is_nil(result)
    end)

    it('overwrites existing file state', function()
      local file_path = '/tmp/overwrite.cpp'

      cache.set_file_state(file_path, 'atcoder', 'abc123', 'a', 'cpp')
      cache.set_file_state(file_path, 'codeforces', '1934', 'b', 'python')

      local result = cache.get_file_state(file_path)

      assert.is_not_nil(result)
      assert.equals('codeforces', result.platform)
      assert.equals('1934', result.contest_id)
      assert.equals('b', result.problem_id)
      assert.equals('python', result.language)
    end)
  end)

  describe('cache management', function()
    it('clears all cache data', function()
      cache.set_contest_data('atcoder', 'test_contest', { { id = 'A' } })
      cache.set_contest_data('codeforces', 'test_contest', { { id = 'B' } })
      cache.set_file_state('/tmp/test.cpp', 'atcoder', 'abc123', 'a', 'cpp')

      cache.clear_all()

      assert.is_nil(cache.get_contest_data('atcoder', 'test_contest'))
      assert.is_nil(cache.get_contest_data('codeforces', 'test_contest'))
      assert.is_nil(cache.get_file_state('/tmp/test.cpp'))
    end)

    it('clears cache for specific platform', function()
      cache.set_contest_data('atcoder', 'test_contest', { { id = 'A' } })
      cache.set_contest_data('codeforces', 'test_contest', { { id = 'B' } })
      cache.set_contest_list('atcoder', { { id = '123', name = 'Test' } })
      cache.set_contest_list('codeforces', { { id = '456', name = 'Test' } })

      cache.clear_platform('atcoder')

      assert.is_nil(cache.get_contest_data('atcoder', 'test_contest'))
      assert.is_nil(cache.get_contest_list('atcoder'))
      assert.is_not_nil(cache.get_contest_data('codeforces', 'test_contest'))
      assert.is_not_nil(cache.get_contest_list('codeforces'))
    end)

    it('handles clear platform for non-existent platform', function()
      assert.has_no_errors(function()
        cache.clear_platform('nonexistent')
      end)
    end)
  end)
end)
