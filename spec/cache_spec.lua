describe('cp.cache', function()
  local cache

  before_each(function()
    cache = require('cp.cache')
    cache.load()
  end)

  after_each(function()
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
end)
