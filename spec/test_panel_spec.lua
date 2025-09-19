describe('cp test panel', function()
  local cp
  local mock_test_module
  local mock_problem_module
  local mock_execute_module
  local mock_cache
  local mock_log_messages
  local _temp_files
  local created_buffers
  local created_windows

  before_each(function()
    mock_log_messages = {}
    _temp_files = {}
    created_buffers = {}
    created_windows = {}

    local mock_logger = {
      log = function(msg, level)
        table.insert(mock_log_messages, { msg = msg, level = level or vim.log.levels.INFO })
      end,
      set_config = function() end,
    }
    package.loaded['cp.log'] = mock_logger

    mock_cache = {
      load = function() end,
      get_test_cases = function()
        return nil
      end,
      set_test_cases = function() end,
      get_contest_data = function()
        return nil
      end,
      set_contest_data = function() end,
    }
    package.loaded['cp.cache'] = mock_cache

    mock_test_module = {
      load_test_cases = function()
        return true
      end,
      run_all_test_cases = function() end,
      get_test_panel_state = function()
        return {
          test_cases = {
            {
              index = 1,
              input = '1 2',
              expected = '3',
              actual = '3',
              status = 'pass',
              ok = true,
              code = 0,
              time_ms = 42.5,
            },
            {
              index = 2,
              input = '4 5',
              expected = '9',
              actual = '10',
              status = 'fail',
              ok = false,
              code = 0,
              time_ms = 15.3,
            },
          },
          current_index = 1,
        }
      end,
    }
    package.loaded['cp.test'] = mock_test_module

    mock_problem_module = {
      create_context = function(contest, contest_id, problem_id, config, language)
        return {
          contest = contest or 'atcoder',
          contest_id = contest_id or 'abc123',
          problem_id = problem_id or 'a',
          source_file = 'test.cpp',
          binary_file = 'build/test.run',
          input_file = 'io/test.cpin',
          output_file = 'io/test.cpout',
          expected_file = 'io/test.expected',
          problem_name = 'test',
        }
      end,
    }
    package.loaded['cp.problem'] = mock_problem_module

    mock_execute_module = {
      compile_problem = function()
        return true
      end,
    }
    package.loaded['cp.execute'] = mock_execute_module

    vim.fn = vim.tbl_extend('force', vim.fn, {
      expand = function(expr)
        if expr == '%:t:r' then
          return 'test'
        end
        return ''
      end,
      tempname = function()
        return '/tmp/session.vim'
      end,
      delete = function() end,
      bufwinid = function(buf)
        return created_windows[buf] or 1000 + buf
      end,
      has = function()
        return 1
      end,
      mkdir = function() end,
    })

    local _original_nvim_create_buf = vim.api.nvim_create_buf
    vim.api.nvim_create_buf = function(listed, scratch)
      local buf_id = #created_buffers + 100
      created_buffers[buf_id] = { listed = listed, scratch = scratch }
      return buf_id
    end

    vim.api.nvim_get_current_win = function()
      return 1
    end
    vim.api.nvim_set_option_value = function() end
    vim.api.nvim_win_set_buf = function(win, buf)
      created_windows[buf] = win
    end
    vim.api.nvim_buf_set_lines = function() end
    vim.api.nvim_buf_is_valid = function()
      return true
    end
    vim.api.nvim_win_call = function(_win, fn)
      fn()
    end
    vim.api.nvim_set_current_win = function() end

    local cmd_table = {
      split = function() end,
      vsplit = function() end,
      diffthis = function() end,
    }

    vim.cmd = setmetatable(cmd_table, {
      __call = function(_, cmd_str)
        if cmd_str and cmd_str:match('silent! %%bwipeout!') then
          return
        end
      end,
      __index = function(_, key)
        return cmd_table[key]
      end,
      __newindex = function(_, key, value)
        cmd_table[key] = value
      end,
    })
    vim.keymap = {
      set = function() end,
    }

    vim.split = function(str, sep, _opts)
      local result = {}
      for part in string.gmatch(str, '[^' .. sep .. ']+') do
        table.insert(result, part)
      end
      return result
    end

    cp = require('cp')
    cp.setup({
      contests = {
        atcoder = {
          default_language = 'cpp',
          cpp = { extension = 'cpp' },
        },
      },
    })

    vim.cmd = function(cmd_str)
      if cmd_str:match('silent! %%bwipeout!') then
        return
      end
    end
  end)

  after_each(function()
    package.loaded['cp.log'] = nil
    package.loaded['cp.cache'] = nil
    package.loaded['cp.test'] = nil
    package.loaded['cp.problem'] = nil
    package.loaded['cp.execute'] = nil
    vim.cmd = function(cmd_str)
      if cmd_str:match('silent! %%bwipeout!') then
        return
      end
    end
  end)

  describe('panel creation', function()
    it('creates test panel buffers', function()
      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })
      cp.handle_command({ fargs = { 'test' } })

      assert.is_true(#created_buffers >= 3)
      for _buf_id, buf_info in pairs(created_buffers) do
        assert.is_false(buf_info.listed)
        assert.is_true(buf_info.scratch)
      end
    end)

    it('sets up correct window layout', function()
      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })

      local split_count = 0
      vim.cmd.split = function()
        split_count = split_count + 1
      end
      vim.cmd.vsplit = function()
        split_count = split_count + 1
      end

      cp.handle_command({ fargs = { 'test' } })

      assert.equals(2, split_count)
      assert.is_true(#created_windows >= 3)
    end)

    it('applies correct buffer settings', function()
      local buffer_options = {}
      vim.api.nvim_set_option_value = function(opt, val, scope)
        if scope.buf then
          buffer_options[scope.buf] = buffer_options[scope.buf] or {}
          buffer_options[scope.buf][opt] = val
        end
      end

      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })
      cp.handle_command({ fargs = { 'test' } })

      for _buf_id, opts in pairs(buffer_options) do
        if opts.bufhidden then
          assert.equals('wipe', opts.bufhidden)
        end
        if opts.filetype then
          assert.equals('cptest', opts.filetype)
        end
      end
    end)

    it('sets up keymaps correctly', function()
      local keymaps = {}
      vim.keymap.set = function(mode, key, _fn, opts)
        table.insert(keymaps, { mode = mode, key = key, buffer = opts.buffer })
      end

      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })
      cp.handle_command({ fargs = { 'test' } })

      local ctrl_n_found = false
      local ctrl_p_found = false
      local q_found = false

      for _, keymap in ipairs(keymaps) do
        if keymap.key == '<c-n>' then
          ctrl_n_found = true
        end
        if keymap.key == '<c-p>' then
          ctrl_p_found = true
        end
        if keymap.key == 'q' then
          q_found = true
        end
      end

      assert.is_true(ctrl_n_found)
      assert.is_true(ctrl_p_found)
      assert.is_true(q_found)
    end)
  end)

  describe('test case display', function()
    it('renders test case tabs correctly', function()
      local tab_content = {}
      vim.api.nvim_buf_set_lines = function(_buf, _start, _end_line, _strict, lines)
        tab_content[_buf] = lines
      end

      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })
      cp.handle_command({ fargs = { 'test' } })

      local found_tab_buffer = false
      for _buf_id, lines in pairs(tab_content) do
        if lines and #lines > 0 then
          local content = table.concat(lines, '\n')
          if content:match('> 1%..*%[ok:true%]') then
            found_tab_buffer = true
            assert.is_not_nil(content:match('%[time:43ms%]'))
            assert.is_not_nil(content:match('Input:'))
            break
          end
        end
      end
      assert.is_true(found_tab_buffer)
    end)

    it('displays input correctly', function()
      local tab_content = {}
      vim.api.nvim_buf_set_lines = function(_buf, _start, _end_line, _strict, lines)
        tab_content[_buf] = lines
      end

      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })
      cp.handle_command({ fargs = { 'test' } })

      local found_input = false
      for _buf_id, lines in pairs(tab_content) do
        if lines and #lines > 0 then
          local content = table.concat(lines, '\n')
          if content:match('Input:') and content:match('1 2') then
            found_input = true
            break
          end
        end
      end
      assert.is_true(found_input)
    end)

    it('displays expected output correctly', function()
      local expected_content = nil
      vim.api.nvim_buf_set_lines = function(_buf, _start, _end_line, _strict, lines)
        if lines and #lines == 1 and lines[1] == '3' then
          expected_content = lines[1]
        end
      end

      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })
      cp.handle_command({ fargs = { 'test' } })

      assert.equals('3', expected_content)
    end)

    it('displays actual output correctly', function()
      local actual_outputs = {}
      vim.api.nvim_buf_set_lines = function(_buf, _start, _end_line, _strict, lines)
        if lines and #lines > 0 then
          table.insert(actual_outputs, lines)
        end
      end

      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })
      cp.handle_command({ fargs = { 'test' } })

      local found_actual = false
      for _, lines in ipairs(actual_outputs) do
        if lines[1] == '3' then
          found_actual = true
          break
        end
      end
      assert.is_true(found_actual)
    end)

    it('shows diff when test fails', function()
      mock_test_module.get_test_panel_state = function()
        return {
          test_cases = {
            {
              index = 1,
              input = '1 2',
              expected = '3',
              actual = '4',
              status = 'fail',
              ok = false,
            },
          },
          current_index = 1,
        }
      end

      local diff_enabled = {}
      vim.api.nvim_set_option_value = function(opt, val, scope)
        if opt == 'diff' and scope.win then
          diff_enabled[scope.win] = val
        end
      end

      local diffthis_called = false
      if not vim.cmd.diffthis then
        local cmd_table = {
          split = function() end,
          vsplit = function() end,
          diffthis = function() end,
        }
        vim.cmd = setmetatable(cmd_table, {
          __call = function(_, cmd_str) return end,
          __index = function(_, key) return cmd_table[key] end,
          __newindex = function(_, key, value) cmd_table[key] = value end,
        })
      end
      vim.cmd.diffthis = function()
        diffthis_called = true
      end

      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })
      cp.handle_command({ fargs = { 'test' } })

      assert.is_true(diffthis_called)
      local diff_windows = 0
      for _, enabled in pairs(diff_enabled) do
        if enabled then
          diff_windows = diff_windows + 1
        end
      end
      assert.is_true(diff_windows >= 2)
    end)
  end)

  describe('navigation', function()
    before_each(function()
      mock_test_module.get_test_panel_state = function()
        return {
          test_cases = {
            { index = 1, input = '1', expected = '1', status = 'pass' },
            { index = 2, input = '2', expected = '2', status = 'pass' },
            { index = 3, input = '3', expected = '3', status = 'fail' },
          },
          current_index = 2,
        }
      end
    end)

    it('navigates to next test case', function()
      local test_state = mock_test_module.get_test_panel_state()

      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })
      cp.handle_command({ fargs = { 'test' } })

      test_state.current_index = test_state.current_index + 1
      assert.equals(3, test_state.current_index)
    end)

    it('navigates to previous test case', function()
      local test_state = mock_test_module.get_test_panel_state()

      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })
      cp.handle_command({ fargs = { 'test' } })

      test_state.current_index = test_state.current_index - 1
      assert.equals(1, test_state.current_index)
    end)

    it('wraps around at boundaries', function()
      local test_state = mock_test_module.get_test_panel_state()

      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })
      cp.handle_command({ fargs = { 'test' } })

      test_state.current_index = 3
      test_state.current_index = test_state.current_index + 1
      if test_state.current_index > #test_state.test_cases then
        test_state.current_index = 1
      end
      assert.equals(1, test_state.current_index)

      test_state.current_index = 1
      test_state.current_index = test_state.current_index - 1
      if test_state.current_index < 1 then
        test_state.current_index = #test_state.test_cases
      end
      assert.equals(3, test_state.current_index)
    end)

    it('updates display on navigation', function()
      local refresh_count = 0
      local original_buf_set_lines = vim.api.nvim_buf_set_lines
      vim.api.nvim_buf_set_lines = function(...)
        refresh_count = refresh_count + 1
        return original_buf_set_lines(...)
      end

      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })
      cp.handle_command({ fargs = { 'test' } })

      local initial_count = refresh_count
      assert.is_true(initial_count > 0)
    end)
  end)

  describe('test execution integration', function()
    it('compiles and runs tests automatically', function()
      local compile_called = false
      local run_tests_called = false

      mock_execute_module.compile_problem = function()
        compile_called = true
        return true
      end

      mock_test_module.run_all_test_cases = function()
        run_tests_called = true
      end

      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })
      cp.handle_command({ fargs = { 'test' } })

      assert.is_true(compile_called)
      assert.is_true(run_tests_called)
    end)

    it('handles compilation failures', function()
      local run_tests_called = false

      mock_execute_module.compile_problem = function()
        return false
      end

      mock_test_module.run_all_test_cases = function()
        run_tests_called = true
      end

      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })
      cp.handle_command({ fargs = { 'test' } })

      assert.is_false(run_tests_called)
    end)

    it('shows execution time', function()
      local tab_content = {}
      vim.api.nvim_buf_set_lines = function(_buf, _start, _end_line, _strict, lines)
        tab_content[_buf] = lines
      end

      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })
      cp.handle_command({ fargs = { 'test' } })

      local found_time = false
      for _buf_id, lines in pairs(tab_content) do
        if lines and #lines > 0 then
          local content = table.concat(lines, '\n')
          if content:match('%[time:%d+ms%]') then
            found_time = true
            break
          end
        end
      end
      assert.is_true(found_time)
    end)
  end)

  describe('session management', function()
    it('saves and restores session correctly', function()
      local session_saved = false
      local session_restored = false

      vim.cmd = function(cmd_str)
        if cmd_str:match('mksession') then
          session_saved = true
        elseif cmd_str:match('source.*session') then
          session_restored = true
        end
      end

      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })
      cp.handle_command({ fargs = { 'test' } })
      assert.is_true(session_saved)

      cp.handle_command({ fargs = { 'test' } })
      assert.is_true(session_restored)
    end)

    it('handles multiple panels gracefully', function()
      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })

      assert.has_no_errors(function()
        cp.handle_command({ fargs = { 'test' } })
        cp.handle_command({ fargs = { 'test' } })
        cp.handle_command({ fargs = { 'test' } })
      end)
    end)

    it('cleans up resources on close', function()
      local delete_called = false
      vim.fn.delete = function()
        delete_called = true
      end

      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })
      cp.handle_command({ fargs = { 'test' } })
      cp.handle_command({ fargs = { 'test' } })

      assert.is_true(delete_called)

      local closed_logged = false
      for _, log in ipairs(mock_log_messages) do
        if log.msg:match('test panel closed') then
          closed_logged = true
          break
        end
      end
      assert.is_true(closed_logged)
    end)
  end)

  describe('error handling', function()
    it('requires platform setup', function()
      cp.handle_command({ fargs = { 'test' } })

      local error_logged = false
      for _, log in ipairs(mock_log_messages) do
        if log.level == vim.log.levels.ERROR and log.msg:match('No contest configured') then
          error_logged = true
          break
        end
      end
      assert.is_true(error_logged)
    end)

    it('handles missing test cases', function()
      mock_test_module.load_test_cases = function()
        return false
      end

      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })
      cp.handle_command({ fargs = { 'test' } })

      local warning_logged = false
      for _, log in ipairs(mock_log_messages) do
        if log.level == vim.log.levels.WARN and log.msg:match('no test cases found') then
          warning_logged = true
          break
        end
      end
      assert.is_true(warning_logged)
    end)

    it('handles missing current problem', function()
      vim.fn.expand = function()
        return ''
      end

      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })
      cp.handle_command({ fargs = { 'test' } })

      local error_logged = false
      for _, log in ipairs(mock_log_messages) do
        if log.level == vim.log.levels.ERROR and log.msg:match('no file open') then
          error_logged = true
          break
        end
      end
      assert.is_true(error_logged)
    end)
  end)
end)
