describe('cp.config', function()
  local config
  local spec_helper = require('spec.spec_helper')

  before_each(function()
    spec_helper.setup()
    config = require('cp.config')
  end)

  after_each(function()
    spec_helper.teardown()
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

    it('allows custom extensions', function()
      local custom_config = {
        contests = {
          test_contest = {
            cpp = { extension = 'custom' },
          },
        },
      }

      assert.has_no.errors(function()
        config.setup(custom_config)
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
      it('validates ansi is boolean', function()
        local invalid_config = {
          run_panel = { ansi = 'invalid' },
        }

        assert.has_error(function()
          config.setup(invalid_config)
        end, 'ansi: expected ansi color parsing must be enabled xor disabled, got string')
      end)

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
          run_panel = { next_test_key = '' },
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
            ansi = false,
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

    describe('auto-configuration', function()
      it('sets default extensions for cpp and python', function()
        local user_config = {
          contests = {
            test = {
              cpp = { compile = { 'g++' } },
              python = { test = { 'python3' } },
            },
          },
        }

        local result = config.setup(user_config)

        assert.equals('cpp', result.contests.test.cpp.extension)
        assert.equals('py', result.contests.test.python.extension)
      end)

      it('sets default_language to cpp when available', function()
        local user_config = {
          contests = {
            test = {
              cpp = { compile = { 'g++' } },
              python = { test = { 'python3' } },
            },
          },
        }

        local result = config.setup(user_config)

        assert.equals('cpp', result.contests.test.default_language)
      end)

      it('sets default_language to first available when cpp not present', function()
        local user_config = {
          contests = {
            test = {
              python = { test = { 'python3' } },
            },
          },
        }

        local result = config.setup(user_config)

        assert.equals('python', result.contests.test.default_language)
      end)

      it('preserves explicit default_language', function()
        local user_config = {
          contests = {
            test = {
              cpp = { compile = { 'g++' } },
              python = { test = { 'python3' } },
              default_language = 'python',
            },
          },
        }

        local result = config.setup(user_config)

        assert.equals('python', result.contests.test.default_language)
      end)

      it('errors when no language configurations exist', function()
        local invalid_config = {
          contests = {
            test = {},
          },
        }

        assert.has_error(function()
          config.setup(invalid_config)
        end, 'No language configurations found')
      end)

      it('allows custom language names', function()
        local user_config = {
          contests = {
            test = {
              rust = {
                compile = { 'rustc', '{source}', '-o', '{binary}' },
                test = { '{binary}' },
                extension = 'rs',
              },
              cpp = { compile = { 'g++' } },
            },
          },
        }

        assert.has_no.errors(function()
          local result = config.setup(user_config)
          assert.equals('cpp', result.contests.test.default_language)
        end)
      end)
    end)

    describe('picker validation', function()
      it('validates picker is valid value', function()
        local invalid_config = {
          picker = 'invalid_picker',
        }

        assert.has_error(function()
          config.setup(invalid_config)
        end, "Invalid picker 'invalid_picker'. Must be 'telescope' or 'fzf-lua'")
      end)

      it('allows nil picker', function()
        assert.has_no.errors(function()
          local result = config.setup({ picker = nil })
          assert.is_nil(result.picker)
        end)
      end)

      it('allows telescope picker without checking availability', function()
        assert.has_no.errors(function()
          local result = config.setup({ picker = 'telescope' })
          assert.equals('telescope', result.picker)
        end)
      end)

      it('allows fzf-lua picker without checking availability', function()
        assert.has_no.errors(function()
          local result = config.setup({ picker = 'fzf-lua' })
          assert.equals('fzf-lua', result.picker)
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
