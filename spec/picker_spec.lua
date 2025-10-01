describe('cp.picker', function()
  local picker
  local spec_helper = require('spec.spec_helper')

  before_each(function()
    spec_helper.setup()
    picker = require('cp.pickers')
  end)

  after_each(function()
    spec_helper.teardown()
  end)

  describe('get_contests_for_platform', function()
    it('returns empty list when scraper fails', function()
      vim.system = function(_, _)
        return {
          wait = function()
            return { code = 1, stderr = 'test error' }
          end,
        }
      end

      local contests = picker.get_contests_for_platform('test_platform')
      assert.is_table(contests)
      assert.equals(0, #contests)
    end)

    it('returns empty list when JSON is invalid', function()
      vim.system = function(_, _)
        return {
          wait = function()
            return { code = 0, stdout = 'invalid json' }
          end,
        }
      end

      local contests = picker.get_contests_for_platform('test_platform')
      assert.is_table(contests)
      assert.equals(0, #contests)
    end)

    it('returns contest list when scraper succeeds', function()
      local cache = require('cp.cache')
      local utils = require('cp.utils')

      cache.load = function() end
      cache.get_contest_list = function()
        return nil
      end
      cache.set_contest_list = function() end

      utils.setup_python_env = function()
        return true
      end
      utils.get_plugin_path = function()
        return '/test/path'
      end

      vim.system = function(_, _)
        return {
          wait = function()
            return {
              code = 0,
              stdout = vim.json.encode({
                success = true,
                contests = {
                  {
                    id = 'abc123',
                    name = 'AtCoder Beginner Contest 123',
                    display_name = 'Beginner Contest 123 (ABC)',
                  },
                  {
                    id = '1951',
                    name = 'Educational Round 168',
                    display_name = 'Educational Round 168',
                  },
                },
              }),
            }
          end,
        }
      end

      local contests = picker.get_contests_for_platform('test_platform')
      assert.is_table(contests)
      assert.equals(2, #contests)
      assert.equals('abc123', contests[1].id)
      assert.equals('AtCoder Beginner Contest 123', contests[1].name)
      assert.equals('Beginner Contest 123 (ABC)', contests[1].display_name)
    end)
  end)

  describe('get_problems_for_contest', function()
    it('returns problems from cache when available', function()
      local cache = require('cp.cache')
      cache.load = function() end
      cache.get_contest_data = function(_, _)
        return {
          problems = {
            { id = 'a', name = 'Problem A' },
            { id = 'b', name = 'Problem B' },
          },
        }
      end

      local problems = picker.get_problems_for_contest('test_platform', 'test_contest')
      assert.is_table(problems)
      assert.equals(2, #problems)
      assert.equals('a', problems[1].id)
      assert.equals('Problem A', problems[1].name)
      assert.equals('Problem A', problems[1].display_name)
    end)

    it('falls back to scraping when cache miss', function()
      local cache = require('cp.cache')
      local utils = require('cp.utils')

      cache.load = function() end
      cache.get_contest_data = function(_, _)
        return nil
      end
      cache.set_contest_data = function() end

      utils.setup_python_env = function()
        return true
      end
      utils.get_plugin_path = function()
        return '/tmp'
      end

      vim.system = function()
        return {
          wait = function()
            return {
              code = 0,
              stdout = vim.json.encode({
                success = true,
                problems = {
                  { id = 'x', name = 'Problem X' },
                },
              }),
            }
          end,
        }
      end

      picker = spec_helper.fresh_require('cp.pickers', { 'cp.pickers.init' })

      local problems = picker.get_problems_for_contest('test_platform', 'test_contest')
      assert.is_table(problems)
      assert.equals(1, #problems)
      assert.equals('x', problems[1].id)
    end)

    it('returns empty list when scraping fails', function()
      local cache = require('cp.cache')
      local utils = require('cp.utils')

      cache.load = function() end
      cache.get_contest_data = function(_, _)
        return nil
      end

      utils.setup_python_env = function()
        return true
      end
      utils.get_plugin_path = function()
        return '/tmp'
      end

      vim.system = function()
        return {
          wait = function()
            return {
              code = 1,
              stderr = 'Scraping failed',
            }
          end,
        }
      end

      picker = spec_helper.fresh_require('cp.pickers', { 'cp.pickers.init' })

      local problems = picker.get_problems_for_contest('test_platform', 'test_contest')
      assert.is_table(problems)
      assert.equals(0, #problems)
    end)
  end)
end)
