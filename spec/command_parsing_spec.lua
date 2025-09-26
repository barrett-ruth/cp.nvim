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

    local mock_setup = {
      set_platform = function()
        return true
      end,
      setup_contest = function() end,
      navigate_problem = function() end,
      setup_problem = function() end,
      scrape_remaining_problems = function() end,
    }
    package.loaded['cp.setup'] = mock_setup

    local mock_state = {
      get_platform = function()
        return 'atcoder'
      end,
      get_contest_id = function()
        return 'abc123'
      end,
      get_problem_id = function()
        return 'a'
      end,
      set_platform = function() end,
      set_contest_id = function() end,
      set_problem_id = function() end,
    }
    package.loaded['cp.state'] = mock_state

    local mock_ui_panel = {
      toggle_run_panel = function() end,
    }
    package.loaded['cp.ui.panel'] = mock_ui_panel

    local mock_cache = {
      load = function() end,
      get_contest_data = function()
        return {
          problems = {
            { id = 'a', name = 'Problem A' },
            { id = 'b', name = 'Problem B' },
          },
        }
      end,
    }
    package.loaded['cp.cache'] = mock_cache

    local mock_restore = {
      restore_from_current_file = function()
        logged_messages[#logged_messages + 1] =
          { msg = 'No file is currently open', level = vim.log.levels.ERROR }
      end,
    }
    package.loaded['cp.restore'] = mock_restore

    local mock_picker = {
      handle_pick_action = function() end,
    }
    package.loaded['cp.commands.picker'] = mock_picker

    local mock_cache_commands = {
      handle_cache_command = function(cmd)
        if cmd.subcommand == 'clear' then
          if cmd.platform then
            local constants = require('cp.constants')
            if vim.tbl_contains(constants.PLATFORMS, cmd.platform) then
              logged_messages[#logged_messages + 1] = { msg = 'cleared cache for ' .. cmd.platform }
            else
              logged_messages[#logged_messages + 1] =
                { msg = 'unknown platform: ' .. cmd.platform, level = vim.log.levels.ERROR }
            end
          else
            logged_messages[#logged_messages + 1] = { msg = 'cleared all cache' }
          end
        end
      end,
    }
    package.loaded['cp.commands.cache'] = mock_cache_commands

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
    package.loaded['cp.setup'] = nil
    package.loaded['cp.state'] = nil
    package.loaded['cp.ui.panel'] = nil
    package.loaded['cp.cache'] = nil
    package.loaded['cp.restore'] = nil
    package.loaded['cp.commands.picker'] = nil
    package.loaded['cp.commands.cache'] = nil
    package.loaded['cp'] = nil
    package.loaded['cp.commands.init'] = nil
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
        if
          log_entry.level == vim.log.levels.ERROR
          and log_entry.msg:match('cache command requires subcommand')
        then
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
        if
          log_entry.level == vim.log.levels.ERROR
          and log_entry.msg:match('unknown cache subcommand')
        then
          error_logged = true
          break
        end
      end
      assert.is_true(error_logged)
    end)
  end)

  describe('CP command completion', function()
    local complete_fn

    before_each(function()
      package.loaded['cp'] = nil
      package.loaded['cp.cache'] = nil

      complete_fn = function(ArgLead, CmdLine, _)
        local constants = require('cp.constants')
        local platforms = constants.PLATFORMS
        local actions = constants.ACTIONS

        local args = vim.split(vim.trim(CmdLine), '%s+')
        local num_args = #args
        if CmdLine:sub(-1) == ' ' then
          num_args = num_args + 1
        end

        if num_args == 2 then
          local candidates = {}
          local state = require('cp.state')
          if state.get_platform() and state.get_contest_id() then
            vim.list_extend(candidates, actions)
            local cache = require('cp.cache')
            cache.load()
            local contest_data =
              cache.get_contest_data(state.get_platform(), state.get_contest_id())
            if contest_data and contest_data.problems then
              for _, problem in ipairs(contest_data.problems) do
                table.insert(candidates, problem.id)
              end
            end
          else
            vim.list_extend(candidates, platforms)
            table.insert(candidates, 'cache')
            table.insert(candidates, 'pick')
          end
          return vim.tbl_filter(function(cmd)
            return cmd:find(ArgLead, 1, true) == 1
          end, candidates)
        elseif num_args == 3 then
          if args[2] == 'cache' then
            return vim.tbl_filter(function(cmd)
              return cmd:find(ArgLead, 1, true) == 1
            end, { 'clear' })
          end
        elseif num_args == 4 then
          if args[2] == 'cache' and args[3] == 'clear' then
            return vim.tbl_filter(function(cmd)
              return cmd:find(ArgLead, 1, true) == 1
            end, platforms)
          elseif vim.tbl_contains(platforms, args[2]) then
            local cache = require('cp.cache')
            cache.load()
            local contest_data = cache.get_contest_data(args[2], args[3])
            if contest_data and contest_data.problems then
              local candidates = {}
              for _, problem in ipairs(contest_data.problems) do
                table.insert(candidates, problem.id)
              end
              return vim.tbl_filter(function(cmd)
                return cmd:find(ArgLead, 1, true) == 1
              end, candidates)
            end
          end
        end
        return {}
      end

      package.loaded['cp.state'] = {
        get_platform = function()
          return nil
        end,
        get_contest_id = function()
          return nil
        end,
      }

      package.loaded['cp.cache'] = {
        load = function() end,
        get_contest_data = function()
          return nil
        end,
      }
    end)

    after_each(function()
      package.loaded['cp'] = nil
      package.loaded['cp.cache'] = nil
    end)

    it('completes platforms and global actions when no contest context', function()
      local result = complete_fn('', 'CP ', 3)

      assert.is_table(result)

      local has_atcoder = false
      local has_codeforces = false
      local has_cses = false
      local has_cache = false
      local has_pick = false
      local has_run = false
      local has_next = false
      local has_prev = false

      for _, item in ipairs(result) do
        if item == 'atcoder' then
          has_atcoder = true
        end
        if item == 'codeforces' then
          has_codeforces = true
        end
        if item == 'cses' then
          has_cses = true
        end
        if item == 'cache' then
          has_cache = true
        end
        if item == 'pick' then
          has_pick = true
        end
        if item == 'run' then
          has_run = true
        end
        if item == 'next' then
          has_next = true
        end
        if item == 'prev' then
          has_prev = true
        end
      end

      assert.is_true(has_atcoder)
      assert.is_true(has_codeforces)
      assert.is_true(has_cses)
      assert.is_true(has_cache)
      assert.is_true(has_pick)
      assert.is_false(has_run)
      assert.is_false(has_next)
      assert.is_false(has_prev)
    end)

    it('completes all actions and problems when contest context exists', function()
      package.loaded['cp.state'] = {
        get_platform = function()
          return 'atcoder'
        end,
        get_contest_id = function()
          return 'abc350'
        end,
      }
      package.loaded['cp.cache'] = {
        load = function() end,
        get_contest_data = function()
          return {
            problems = {
              { id = 'a' },
              { id = 'b' },
              { id = 'c' },
            },
          }
        end,
      }

      local result = complete_fn('', 'CP ', 3)

      assert.is_table(result)

      local items = {}
      for _, item in ipairs(result) do
        items[item] = true
      end

      assert.is_true(items['run'])
      assert.is_true(items['next'])
      assert.is_true(items['prev'])
      assert.is_true(items['pick'])
      assert.is_true(items['cache'])

      assert.is_true(items['a'])
      assert.is_true(items['b'])
      assert.is_true(items['c'])
    end)

    it('completes cache subcommands', function()
      local result = complete_fn('c', 'CP cache c', 10)

      assert.is_table(result)
      assert.equals(1, #result)
      assert.equals('clear', result[1])
    end)

    it('completes cache subcommands with exact match', function()
      local result = complete_fn('clear', 'CP cache clear', 14)

      assert.is_table(result)
      assert.equals(1, #result)
      assert.equals('clear', result[1])
    end)

    it('completes platforms for cache clear', function()
      local result = complete_fn('a', 'CP cache clear a', 16)

      assert.is_table(result)

      local has_atcoder = false
      local has_cache = false

      for _, item in ipairs(result) do
        if item == 'atcoder' then
          has_atcoder = true
        end
        if item == 'cache' then
          has_cache = true
        end
      end

      assert.is_true(has_atcoder)
      assert.is_false(has_cache)
    end)

    it('filters completions based on current input', function()
      local result = complete_fn('at', 'CP at', 5)

      assert.is_table(result)
      assert.equals(1, #result)
      assert.equals('atcoder', result[1])
    end)

    it('returns empty array when no matches', function()
      local result = complete_fn('xyz', 'CP xyz', 6)

      assert.is_table(result)
      assert.equals(0, #result)
    end)

    it('handles problem completion for platform contest', function()
      package.loaded['cp.cache'] = {
        load = function() end,
        get_contest_data = function(platform, contest)
          if platform == 'atcoder' and contest == 'abc350' then
            return {
              problems = {
                { id = 'a' },
                { id = 'b' },
              },
            }
          end
          return nil
        end,
      }

      local result = complete_fn('a', 'CP atcoder abc350 a', 18)

      assert.is_table(result)
      assert.equals(1, #result)
      assert.equals('a', result[1])
    end)
  end)
end)
