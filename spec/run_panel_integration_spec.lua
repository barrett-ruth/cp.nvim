describe('run panel state integration', function()
  local cp
  local logged_messages
  local mock_vim_api_calls
  local mock_vim_cmd_calls

  before_each(function()
    logged_messages = {}
    mock_vim_api_calls = {}
    mock_vim_cmd_calls = {}

    local mock_logger = {
      log = function(msg, level)
        table.insert(logged_messages, { msg = msg, level = level })
      end,
      set_config = function() end,
    }

    local mock_cache = {
      load = function() end,
      get_test_cases = function()
        return nil
      end,
      set_test_cases = function() end,
      get_contest_data = function(platform, contest_id)
        if platform == 'atcoder' and contest_id == 'abc123' then
          return {
            problems = {
              { id = 'a', name = 'Problem A' },
              { id = 'b', name = 'Problem B' },
              { id = 'c', name = 'Problem C' },
            },
          }
        end
        return nil
      end,
      set_file_state = function() end,
      get_file_state = function()
        return nil
      end,
    }

    local mock_scrape = {
      scrape_contest_metadata = function()
        return { success = false, error = 'mocked disabled' }
      end,
      scrape_problem = function()
        return { success = false, error = 'mocked disabled' }
      end,
    }

    local mock_problem = {
      create_context = function(platform, contest_id, problem_id, config, language)
        return {
          platform = platform,
          contest_id = contest_id,
          problem_id = problem_id,
          source_file = '/tmp/test.cpp',
          problem_name = problem_id or contest_id,
        }
      end,
    }

    local mock_snippets = {
      setup = function() end,
    }

    local mock_run = {
      load_test_cases = function()
        return false
      end,
      get_run_panel_state = function()
        return { test_cases = {}, current_index = 1 }
      end,
      run_all_test_cases = function() end,
      handle_compilation_failure = function() end,
    }

    local mock_execute = {
      compile_problem = function()
        return { success = true }
      end,
    }

    local mock_run_render = {
      setup_highlights = function() end,
      render_test_list = function()
        return {}, {}
      end,
    }

    local mock_vim = {
      fn = {
        has = function()
          return 1
        end,
        mkdir = function() end,
        expand = function(str)
          if str == '%:t:r' then
            return 'test'
          end
          if str == '%:p' then
            return '/tmp/test.cpp'
          end
          return str
        end,
        tempname = function()
          return '/tmp/test_session'
        end,
        delete = function() end,
      },
      cmd = {
        e = function() end,
        split = function() end,
        vsplit = function() end,
        startinsert = function() end,
        stopinsert = function() end,
        diffthis = function() end,
      },
      api = {
        nvim_get_current_buf = function()
          return 1
        end,
        nvim_get_current_win = function()
          return 1
        end,
        nvim_create_buf = function()
          return 2
        end,
        nvim_set_option_value = function(opt, val, opts)
          table.insert(mock_vim_api_calls, { 'set_option_value', opt, val, opts })
        end,
        nvim_get_option_value = function(opt, opts)
          if opt == 'readonly' then
            return false
          end
          if opt == 'filetype' then
            return 'cpp'
          end
          return nil
        end,
        nvim_win_set_buf = function() end,
        nvim_buf_set_lines = function() end,
        nvim_buf_get_lines = function()
          return { '' }
        end,
        nvim_win_set_cursor = function() end,
        nvim_win_get_cursor = function()
          return { 1, 0 }
        end,
        nvim_create_namespace = function()
          return 1
        end,
        nvim_win_close = function() end,
        nvim_buf_delete = function() end,
        nvim_win_call = function(win, fn)
          fn()
        end,
      },
      keymap = {
        set = function() end,
      },
      schedule = function(fn)
        fn()
      end,
      log = {
        levels = {
          ERROR = 1,
          WARN = 2,
          INFO = 3,
        },
      },
      tbl_contains = function(tbl, val)
        for _, v in ipairs(tbl) do
          if v == val then
            return true
          end
        end
        return false
      end,
      tbl_map = function(fn, tbl)
        local result = {}
        for i, v in ipairs(tbl) do
          result[i] = fn(v)
        end
        return result
      end,
      tbl_filter = function(fn, tbl)
        local result = {}
        for _, v in ipairs(tbl) do
          if fn(v) then
            table.insert(result, v)
          end
        end
        return result
      end,
      split = function(str, sep)
        local result = {}
        for token in string.gmatch(str, '[^' .. sep .. ']+') do
          table.insert(result, token)
        end
        return result
      end,
    }

    package.loaded['cp.log'] = mock_logger
    package.loaded['cp.cache'] = mock_cache
    package.loaded['cp.scrape'] = mock_scrape
    package.loaded['cp.problem'] = mock_problem
    package.loaded['cp.snippets'] = mock_snippets
    package.loaded['cp.run'] = mock_run
    package.loaded['cp.execute'] = mock_execute
    package.loaded['cp.run_render'] = mock_run_render

    _G.vim = mock_vim

    mock_vim.cmd = function(cmd_str)
      table.insert(mock_vim_cmd_calls, cmd_str)
      if cmd_str == 'silent only' then
        -- Simulate closing all windows
      end
    end

    cp = require('cp')
    cp.setup({
      contests = {
        atcoder = {
          default_language = 'cpp',
          cpp = { extension = 'cpp' },
        },
      },
      scrapers = {}, -- Disable scrapers for testing
      run_panel = {
        diff_mode = 'vim',
        toggle_diff_key = 'd',
        next_test_key = 'j',
        prev_test_key = 'k',
        ansi = false,
      },
    })
  end)

  after_each(function()
    package.loaded['cp.log'] = nil
    package.loaded['cp.cache'] = nil
    package.loaded['cp.scrape'] = nil
    package.loaded['cp.problem'] = nil
    package.loaded['cp.snippets'] = nil
    package.loaded['cp.run'] = nil
    package.loaded['cp.execute'] = nil
    package.loaded['cp.run_render'] = nil
    _G.vim = nil
  end)

  describe('run panel state bug fix', function()
    it('properly resets run panel state after navigation', function()
      -- Setup: configure a contest with problems
      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })

      -- Clear previous messages
      logged_messages = {}
      mock_vim_cmd_calls = {}

      -- Step 1: Run cp run to open the test panel
      cp.handle_command({ fargs = { 'run' } })

      -- Verify panel would be opened (no test cases means it logs a warning but state is set)
      local panel_opened = false
      for _, log in ipairs(logged_messages) do
        if log.msg:match('no test cases found') then
          panel_opened = true -- Panel was attempted to open
          break
        end
      end
      assert.is_true(panel_opened, 'First run command should attempt to open panel')

      -- Clear messages and cmd calls for next step
      logged_messages = {}
      mock_vim_cmd_calls = {}

      -- Step 2: Run cp next to navigate to next problem
      cp.handle_command({ fargs = { 'next' } })

      -- Verify that 'silent only' was called (which closes windows)
      local silent_only_called = false
      for _, cmd in ipairs(mock_vim_cmd_calls) do
        if cmd == 'silent only' then
          silent_only_called = true
          break
        end
      end
      assert.is_true(silent_only_called, 'Navigation should close all windows')

      -- Clear messages for final step
      logged_messages = {}

      -- Step 3: Run cp run again - this should try to OPEN the panel, not close it
      cp.handle_command({ fargs = { 'run' } })

      -- Verify panel would be opened again (not closed)
      local panel_opened_again = false
      for _, log in ipairs(logged_messages) do
        if log.msg:match('no test cases found') then
          panel_opened_again = true -- Panel was attempted to open again
          break
        end
      end
      assert.is_true(
        panel_opened_again,
        'Second run command should attempt to open panel, not close it'
      )

      -- Verify no "test panel closed" message
      local panel_closed = false
      for _, log in ipairs(logged_messages) do
        if log.msg:match('test panel closed') then
          panel_closed = true
          break
        end
      end
      assert.is_false(panel_closed, 'Second run command should not close panel')
    end)

    it('handles navigation to previous problem correctly', function()
      -- Setup: configure a contest starting with problem b
      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'b' } })

      -- Clear messages
      logged_messages = {}
      mock_vim_cmd_calls = {}

      -- Open test panel
      cp.handle_command({ fargs = { 'run' } })

      -- Navigate to previous problem (should go to 'a')
      logged_messages = {}
      mock_vim_cmd_calls = {}
      cp.handle_command({ fargs = { 'prev' } })

      -- Verify 'silent only' was called
      local silent_only_called = false
      for _, cmd in ipairs(mock_vim_cmd_calls) do
        if cmd == 'silent only' then
          silent_only_called = true
          break
        end
      end
      assert.is_true(silent_only_called, 'Previous navigation should also close all windows')

      -- Run again - should open panel
      logged_messages = {}
      cp.handle_command({ fargs = { 'run' } })

      local panel_opened = false
      for _, log in ipairs(logged_messages) do
        if log.msg:match('no test cases found') then
          panel_opened = true
          break
        end
      end
      assert.is_true(panel_opened, 'After previous navigation, run should open panel')
    end)
  end)
end)
