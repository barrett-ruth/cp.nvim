describe('cp command parsing', function()
  local cp
  local logged_messages

  before_each(function()
    logged_messages = {}
    local mock_logger = {
      log = function(msg, level)
        table.insert(logged_messages, { msg = msg, level = level })
      end,
      set_config = function() end,
    }
    package.loaded['cp.log'] = mock_logger

    cp = require('cp')
    cp.setup({
      contests = {
        atcoder = {
          default_language = 'cpp',
          cpp = { extension = 'cpp' },
        },
        cses = {
          default_language = 'cpp',
          cpp = { extension = 'cpp' },
        },
      },
    })
  end)

  after_each(function()
    package.loaded['cp.log'] = nil
  end)

  describe('empty arguments', function()
    it('attempts file state restoration for no arguments', function()
      local opts = { fargs = {} }

      cp.handle_command(opts)

      assert.is_true(#logged_messages > 0)
      local error_logged = false
      for _, log_entry in ipairs(logged_messages) do
        if
          log_entry.level == vim.log.levels.ERROR
          and log_entry.msg:match('No file is currently open')
        then
          error_logged = true
          break
        end
      end
      assert.is_true(error_logged)
    end)
  end)

  describe('action commands', function()
    it('handles test action without error', function()
      local opts = { fargs = { 'run' } }

      assert.has_no_errors(function()
        cp.handle_command(opts)
      end)
    end)

    it('handles next action without error', function()
      local opts = { fargs = { 'next' } }

      assert.has_no_errors(function()
        cp.handle_command(opts)
      end)
    end)

    it('handles prev action without error', function()
      local opts = { fargs = { 'prev' } }

      assert.has_no_errors(function()
        cp.handle_command(opts)
      end)
    end)
  end)

  describe('platform commands', function()
    it('handles platform-only command', function()
      local opts = { fargs = { 'atcoder' } }

      assert.has_no_errors(function()
        cp.handle_command(opts)
      end)
    end)

    it('handles contest setup command', function()
      local opts = { fargs = { 'atcoder', 'abc123' } }

      assert.has_no_errors(function()
        cp.handle_command(opts)
      end)
    end)

    it('handles cses problem command', function()
      local opts = { fargs = { 'cses', 'sorting_and_searching', '1234' } }

      assert.has_no_errors(function()
        cp.handle_command(opts)
      end)
    end)

    it('handles full setup command', function()
      local opts = { fargs = { 'atcoder', 'abc123', 'a' } }

      assert.has_no_errors(function()
        cp.handle_command(opts)
      end)
    end)

    it('logs error for too many arguments', function()
      local opts = { fargs = { 'atcoder', 'abc123', 'a', 'b', 'extra' } }

      cp.handle_command(opts)

      local error_logged = false
      for _, log_entry in ipairs(logged_messages) do
        if log_entry.level == vim.log.levels.ERROR then
          error_logged = true
          break
        end
      end
      assert.is_true(error_logged)
    end)
  end)

  describe('language flag parsing', function()
    it('logs error for --lang flag missing value', function()
      local opts = { fargs = { 'run', '--lang' } }

      cp.handle_command(opts)

      local error_logged = false
      for _, log_entry in ipairs(logged_messages) do
        if
          log_entry.level == vim.log.levels.ERROR and log_entry.msg:match('--lang requires a value')
        then
          error_logged = true
          break
        end
      end
      assert.is_true(error_logged)
    end)

    it('handles language with equals format', function()
      local opts = { fargs = { 'atcoder', '--lang=python' } }

      assert.has_no_errors(function()
        cp.handle_command(opts)
      end)
    end)

    it('handles language with space format', function()
      local opts = { fargs = { 'atcoder', '--lang', 'cpp' } }

      assert.has_no_errors(function()
        cp.handle_command(opts)
      end)
    end)

    it('handles contest with language flag', function()
      local opts = { fargs = { 'atcoder', 'abc123', '--lang=python' } }

      assert.has_no_errors(function()
        cp.handle_command(opts)
      end)
    end)
  end)

  describe('debug flag parsing', function()
    it('handles debug flag without error', function()
      local opts = { fargs = { 'run', '--debug' } }

      assert.has_no_errors(function()
        cp.handle_command(opts)
      end)
    end)

    it('handles combined language and debug flags', function()
      local opts = { fargs = { 'run', '--lang=cpp', '--debug' } }

      assert.has_no_errors(function()
        cp.handle_command(opts)
      end)
    end)
  end)

  describe('restore from file', function()
    it('returns restore_from_file type for empty args', function()
      local opts = { fargs = {} }
      local logged_error = false

      cp.handle_command(opts)

      for _, log in ipairs(logged_messages) do
        if log.level == vim.log.levels.ERROR and log.msg:match('No file is currently open') then
          logged_error = true
        end
      end

      assert.is_true(logged_error)
    end)
  end)

  describe('invalid commands', function()
    it('logs error for invalid platform', function()
      local opts = { fargs = { 'invalid_platform' } }

      cp.handle_command(opts)

      local error_logged = false
      for _, log_entry in ipairs(logged_messages) do
        if log_entry.level == vim.log.levels.ERROR then
          error_logged = true
          break
        end
      end
      assert.is_true(error_logged)
    end)

    it('logs error for invalid action', function()
      local opts = { fargs = { 'invalid_action' } }

      cp.handle_command(opts)

      local error_logged = false
      for _, log_entry in ipairs(logged_messages) do
        if log_entry.level == vim.log.levels.ERROR then
          error_logged = true
          break
        end
      end
      assert.is_true(error_logged)
    end)
  end)

  describe('edge cases', function()
    it('handles empty string arguments', function()
      local opts = { fargs = { '' } }

      cp.handle_command(opts)

      local error_logged = false
      for _, log_entry in ipairs(logged_messages) do
        if log_entry.level == vim.log.levels.ERROR then
          error_logged = true
          break
        end
      end
      assert.is_true(error_logged)
    end)

    it('handles flag order variations', function()
      local opts = { fargs = { '--debug', 'run', '--lang=python' } }

      assert.has_no_errors(function()
        cp.handle_command(opts)
      end)
    end)

    it('handles multiple language flags', function()
      local opts = { fargs = { 'run', '--lang=cpp', '--lang=python' } }

      assert.has_no_errors(function()
        cp.handle_command(opts)
      end)
    end)
  end)

  describe('command validation', function()
    it('validates platform names against constants', function()
      local constants = require('cp.constants')

      for _, platform in ipairs(constants.PLATFORMS) do
        local opts = { fargs = { platform } }
        assert.has_no_errors(function()
          cp.handle_command(opts)
        end)
      end
    end)

    it('validates action names against constants', function()
      local constants = require('cp.constants')

      for _, action in ipairs(constants.ACTIONS) do
        local opts = { fargs = { action } }
        assert.has_no_errors(function()
          cp.handle_command(opts)
        end)
      end
    end)
  end)

  describe('cache commands', function()
    it('handles cache clear without platform', function()
      local opts = { fargs = { 'cache', 'clear' } }

      assert.has_no_errors(function()
        cp.handle_command(opts)
      end)

      local success_logged = false
      for _, log_entry in ipairs(logged_messages) do
        if log_entry.msg and log_entry.msg:match('cleared all cache') then
          success_logged = true
          break
        end
      end
      assert.is_true(success_logged)
    end)

    it('handles cache clear with valid platform', function()
      local opts = { fargs = { 'cache', 'clear', 'atcoder' } }

      assert.has_no_errors(function()
        cp.handle_command(opts)
      end)

      local success_logged = false
      for _, log_entry in ipairs(logged_messages) do
        if log_entry.msg and log_entry.msg:match('cleared cache for atcoder') then
          success_logged = true
          break
        end
      end
      assert.is_true(success_logged)
    end)

    it('logs error for cache clear with invalid platform', function()
      local opts = { fargs = { 'cache', 'clear', 'invalid_platform' } }

      cp.handle_command(opts)

      local error_logged = false
      for _, log_entry in ipairs(logged_messages) do
        if log_entry.level == vim.log.levels.ERROR and log_entry.msg:match('unknown platform') then
          error_logged = true
          break
        end
      end
      assert.is_true(error_logged)
    end)

    it('logs error for cache command without subcommand', function()
      local opts = { fargs = { 'cache' } }

      cp.handle_command(opts)

      local error_logged = false
      for _, log_entry in ipairs(logged_messages) do
        if log_entry.level == vim.log.levels.ERROR and log_entry.msg:match('cache command requires subcommand') then
          error_logged = true
          break
        end
      end
      assert.is_true(error_logged)
    end)

    it('logs error for invalid cache subcommand', function()
      local opts = { fargs = { 'cache', 'invalid' } }

      cp.handle_command(opts)

      local error_logged = false
      for _, log_entry in ipairs(logged_messages) do
        if log_entry.level == vim.log.levels.ERROR and log_entry.msg:match('unknown cache subcommand') then
          error_logged = true
          break
        end
      end
      assert.is_true(error_logged)
    end)
  end)
end)
