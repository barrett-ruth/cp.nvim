describe('cp.config', function()
  local config

  before_each(function()
    config = require('cp.config')
  end)

  describe('setup', function()
    it('returns defaults with nil input', function()
      local result = config.setup()

      assert.equals('table', type(result.contests))
      assert.equals('table', type(result.snippets))
      assert.equals('table', type(result.hooks))
      assert.equals('table', type(result.scrapers))
      assert.is_false(result.debug)
      assert.is_nil(result.filename)
    end)

    it('merges user config with defaults', function()
      local user_config = {
        debug = true,
        contests = { test_contest = { cpp = { extension = 'cpp' } } },
      }

      local result = config.setup(user_config)

      assert.is_true(result.debug)
      assert.equals('table', type(result.contests.test_contest))
      assert.equals('table', type(result.scrapers))
    end)

    it('validates extension against supported filetypes', function()
      local invalid_config = {
        contests = {
          test_contest = {
            cpp = { extension = 'invalid' },
          },
        },
      }

      assert.has_error(function()
        config.setup(invalid_config)
      end)
    end)

    it('validates scraper platforms', function()
      local invalid_config = {
        scrapers = { 'invalid_platform' },
      }

      assert.has_error(function()
        config.setup(invalid_config)
      end)
    end)

    it('validates scraper values are strings', function()
      local invalid_config = {
        scrapers = { 123 },
      }

      assert.has_error(function()
        config.setup(invalid_config)
      end)
    end)

    it('validates hook functions', function()
      local invalid_config = {
        hooks = { before_run = 'not_a_function' },
      }

      assert.has_error(function()
        config.setup(invalid_config)
      end)
    end)

    describe('run_panel config validation', function()
      it('validates diff_mode values', function()
        local invalid_config = {
          run_panel = { diff_mode = 'invalid' },
        }

        assert.has_error(function()
          config.setup(invalid_config)
        end)
      end)

      it('validates next_test_key is non-empty string', function()
        local invalid_config = {
          run_panel = { next_test_key = nil },
        }

        assert.has_error(function()
          config.setup(invalid_config)
        end)
      end)

      it('validates prev_test_key is non-empty string', function()
        local invalid_config = {
          run_panel = { prev_test_key = '' },
        }

        assert.has_error(function()
          config.setup(invalid_config)
        end)
      end)

      it('accepts valid run_panel config', function()
        local valid_config = {
          run_panel = {
            diff_mode = 'git',
            next_test_key = 'j',
            prev_test_key = 'k',
          },
        }

        assert.has_no.errors(function()
          config.setup(valid_config)
        end)
      end)
    end)
  end)

  describe('default_filename', function()
    it('generates lowercase contest filename', function()
      local result = config.default_filename('ABC123')
      assert.equals('abc123', result)
    end)

    it('combines contest and problem ids', function()
      local result = config.default_filename('ABC123', 'A')
      assert.equals('abc123a', result)
    end)
  end)
end)
