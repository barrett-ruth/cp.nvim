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

  describe('get_platforms', function()
    it('returns platform list with display names', function()
      local platforms = picker.get_platforms()

      assert.is_table(platforms)
      assert.is_true(#platforms > 0)

      for _, platform in ipairs(platforms) do
        assert.is_string(platform.id)
        assert.is_string(platform.display_name)
        assert.is_not_nil(platform.display_name:match('^%u'))
      end
    end)

    it('includes expected platforms with correct display names', function()
      local platforms = picker.get_platforms()
      local platform_map = {}
      for _, p in ipairs(platforms) do
        platform_map[p.id] = p.display_name
      end

      assert.equals('CodeForces', platform_map['codeforces'])
      assert.equals('AtCoder', platform_map['atcoder'])
      assert.equals('CSES', platform_map['cses'])
    end)
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

      cache.load = function() end
      cache.get_contest_data = function(_, _)
        return nil
      end

      package.loaded['cp.scrape'] = {
        scrape_contest_metadata = function(_, _)
          return {
            success = true,
            problems = {
              { id = 'x', name = 'Problem X' },
            },
          }
        end,
      }

      package.loaded['cp.pickers.init'] = nil
      package.loaded['cp.pickers'] = nil
      picker = require('cp.pickers')

      local problems = picker.get_problems_for_contest('test_platform', 'test_contest')
      assert.is_table(problems)
      assert.equals(1, #problems)
      assert.equals('x', problems[1].id)
    end)

    it('returns empty list when scraping fails', function()
      local cache = require('cp.cache')
      local scrape = require('cp.scrape')

      cache.load = function() end
      cache.get_contest_data = function(_, _)
        return nil
      end
      scrape.scrape_contest_metadata = function(_, _)
        return {
          success = false,
          error = 'test error',
        }
      end

      local problems = picker.get_problems_for_contest('test_platform', 'test_contest')
      assert.is_table(problems)
      assert.equals(0, #problems)
    end)
  end)

  describe('setup_problem', function()
    it('calls cp.handle_command with correct arguments', function()
      local cp = require('cp')
      local called_with = nil

      cp.handle_command = function(opts)
        called_with = opts
      end

      picker.setup_problem('codeforces', '1951', 'a')

      vim.wait(100, function()
        return called_with ~= nil
      end)

      assert.is_table(called_with)
      assert.is_table(called_with.fargs)
      assert.equals('codeforces', called_with.fargs[1])
      assert.equals('1951', called_with.fargs[2])
      assert.equals('a', called_with.fargs[3])
    end)
  end)
end)
