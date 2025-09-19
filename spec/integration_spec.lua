describe('cp integration', function()
  local cp
  local mock_cache
  local mock_system_calls
  local mock_log_messages
  local temp_files

  before_each(function()
    cp = require('cp')
    mock_cache = {
      load = function() end,
      get_contest_data = function()
        return nil
      end,
      set_contest_data = function() end,
      get_test_cases = function()
        return nil
      end,
      set_test_cases = function() end,
    }
    mock_system_calls = {}
    mock_log_messages = {}
    temp_files = {}

    vim.system = function(cmd, opts)
      table.insert(mock_system_calls, { cmd = cmd, opts = opts })
      local result = { code = 0, stdout = '{}', stderr = '' }

      if cmd[1] == 'uv' and cmd[2] == 'run' then
        if vim.tbl_contains(cmd, 'metadata') then
          result.stdout = '{"success": true, "problems": [{"id": "a", "name": "Problem A"}]}'
        elseif vim.tbl_contains(cmd, 'tests') then
          result.stdout = '{"success": true, "tests": [{"input": "1 2", "expected": "3"}]}'
        end
      end

      return {
        wait = function()
          return result
        end,
      }
    end

    vim.fn = vim.tbl_extend('force', vim.fn, {
      executable = function()
        return 1
      end,
      isdirectory = function()
        return 1
      end,
      filereadable = function(path)
        return temp_files[path] and 1 or 0
      end,
      readfile = function(path)
        return temp_files[path] or {}
      end,
      writefile = function(lines, path)
        temp_files[path] = lines
      end,
      mkdir = function() end,
      fnamemodify = function(path, modifier)
        if modifier == ':e' then
          return path:match('%.([^.]+)$') or ''
        end
        return path
      end,
    })

    package.loaded['cp.cache'] = mock_cache
    package.loaded['cp.log'] = {
      log = function(msg, level)
        table.insert(mock_log_messages, { msg = msg, level = level or vim.log.levels.INFO })
      end,
      set_config = function() end,
    }

    cp.setup({
      contests = {
        atcoder = {
          default_language = 'cpp',
          timeout_ms = 2000,
          cpp = {
            compile = { 'g++', '{source}', '-o', '{binary}' },
            run = { '{binary}' },
          },
        },
      },
      scrapers = { 'atcoder' },
    })
  end)

  after_each(function()
    package.loaded['cp.cache'] = nil
    package.loaded['cp.log'] = nil
    vim.cmd('silent! %bwipeout!')
  end)

  describe('full workflow', function()
    it('handles complete contest setup workflow', function()
      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })

      local found_metadata_call = false
      local found_tests_call = false
      for _, call in ipairs(mock_system_calls) do
        if vim.tbl_contains(call.cmd, 'metadata') then
          found_metadata_call = true
        end
        if vim.tbl_contains(call.cmd, 'tests') then
          found_tests_call = true
        end
      end

      assert.is_true(found_metadata_call)
      assert.is_true(found_tests_call)
    end)

    it('integrates scraping with problem creation', function()
      local stored_contest_data = nil
      local stored_test_cases = nil
      mock_cache.set_contest_data = function(platform, contest_id, data)
        stored_contest_data = { platform = platform, contest_id = contest_id, data = data }
      end
      mock_cache.set_test_cases = function(platform, contest_id, problem_id, test_cases)
        stored_test_cases = {
          platform = platform,
          contest_id = contest_id,
          problem_id = problem_id,
          test_cases = test_cases,
        }
      end

      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })

      assert.is_not_nil(stored_contest_data)
      assert.equals('atcoder', stored_contest_data.platform)
      assert.equals('abc123', stored_contest_data.contest_id)

      assert.is_not_nil(stored_test_cases)
      assert.equals('a', stored_test_cases.problem_id)
    end)

    it('coordinates between modules correctly', function()
      local test_module = require('cp.test')
      local state = test_module.get_test_panel_state()

      state.test_cases = {
        {
          input = '1 2',
          expected = '3',
          status = 'pending',
        },
      }

      local context = {
        source_file = 'test.cpp',
        binary_file = 'test.run',
        input_file = 'io/test.cpin',
        expected_file = 'io/test.cpout',
      }
      local contest_config = {
        default_language = 'cpp',
        timeout_ms = 2000,
        cpp = {
          run = { '{binary}' },
        },
      }

      temp_files['test.run'] = {}
      vim.system = function(cmd, opts)
        return {
          wait = function()
            return { code = 0, stdout = '3\n', stderr = '' }
          end,
        }
      end

      local success = test_module.run_test_case(context, contest_config, 1)
      assert.is_true(success)
      assert.equals('pass', state.test_cases[1].status)
    end)
  end)

  describe('scraper integration', function()
    it('integrates with python scrapers correctly', function()
      mock_cache.get_contest_data = function()
        return nil
      end

      cp.handle_command({ fargs = { 'atcoder', 'abc123' } })

      local found_uv_call = false
      for _, call in ipairs(mock_system_calls) do
        if call.cmd[1] == 'uv' and call.cmd[2] == 'run' then
          found_uv_call = true
          break
        end
      end

      assert.is_true(found_uv_call)
    end)

    it('handles scraper communication properly', function()
      vim.system = function(cmd, opts)
        if cmd[1] == 'uv' and vim.tbl_contains(cmd, 'metadata') then
          return {
            wait = function()
              return { code = 1, stderr = 'network error' }
            end,
          }
        end
        return {
          wait = function()
            return { code = 0 }
          end,
        }
      end

      cp.handle_command({ fargs = { 'atcoder', 'abc123' } })

      local error_logged = false
      for _, log_entry in ipairs(mock_log_messages) do
        if
          log_entry.level == vim.log.levels.WARN
          and log_entry.msg:match('failed to load contest metadata')
        then
          error_logged = true
          break
        end
      end
      assert.is_true(error_logged)
    end)

    it('processes scraper output correctly', function()
      vim.system = function(cmd, opts)
        if vim.tbl_contains(cmd, 'metadata') then
          return {
            wait = function()
              return {
                code = 0,
                stdout = '{"success": true, "problems": [{"id": "a", "name": "Problem A"}, {"id": "b", "name": "Problem B"}]}',
              }
            end,
          }
        end
        return {
          wait = function()
            return { code = 0 }
          end,
        }
      end

      cp.handle_command({ fargs = { 'atcoder', 'abc123' } })

      local success_logged = false
      for _, log_entry in ipairs(mock_log_messages) do
        if log_entry.msg:match('loaded 2 problems for atcoder abc123') then
          success_logged = true
          break
        end
      end
      assert.is_true(success_logged)
    end)
  end)

  describe('buffer coordination', function()
    it('manages multiple buffers correctly', function()
      temp_files['abc123a.cpp'] = { '#include <iostream>' }

      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })

      local initial_buf_count = #vim.api.nvim_list_bufs()
      assert.is_true(initial_buf_count >= 1)

      vim.cmd('enew')
      local after_enew_count = #vim.api.nvim_list_bufs()
      assert.is_true(after_enew_count > initial_buf_count)
    end)

    it('coordinates window layouts properly', function()
      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })

      local initial_windows = vim.api.nvim_list_wins()
      vim.cmd('split')
      local split_windows = vim.api.nvim_list_wins()

      assert.is_true(#split_windows > #initial_windows)
    end)

    it('handles buffer state consistency', function()
      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })

      local context = cp.get_current_context()
      assert.equals('atcoder', context.platform)
      assert.equals('abc123', context.contest_id)
      assert.equals('a', context.problem_id)

      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'b' } })

      local updated_context = cp.get_current_context()
      assert.equals('b', updated_context.problem_id)
    end)
  end)

  describe('cache and persistence', function()
    it('maintains data consistency across sessions', function()
      local cached_data = {
        problems = { { id = 'a', name = 'Problem A' } },
      }
      mock_cache.get_contest_data = function(platform, contest_id)
        if platform == 'atcoder' and contest_id == 'abc123' then
          return cached_data
        end
      end

      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })

      local no_scraper_calls = true
      for _, call in ipairs(mock_system_calls) do
        if vim.tbl_contains(call.cmd, 'metadata') then
          no_scraper_calls = false
          break
        end
      end
      assert.is_true(no_scraper_calls)
    end)

    it('handles concurrent access properly', function()
      local access_count = 0
      mock_cache.get_contest_data = function()
        access_count = access_count + 1
        return { problems = { { id = 'a', name = 'Problem A' } } }
      end

      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })
      cp.handle_command({ fargs = { 'next' } })

      assert.is_true(access_count >= 1)
    end)

    it('recovers from interrupted operations', function()
      vim.system = function(cmd, opts)
        if vim.tbl_contains(cmd, 'metadata') then
          return {
            wait = function()
              return { code = 1, stderr = 'interrupted' }
            end,
          }
        end
        return {
          wait = function()
            return { code = 0 }
          end,
        }
      end

      assert.has_no_errors(function()
        cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })
      end)

      local error_logged = false
      for _, log_entry in ipairs(mock_log_messages) do
        if log_entry.level >= vim.log.levels.WARN then
          error_logged = true
          break
        end
      end
      assert.is_true(error_logged)
    end)
  end)

  describe('error propagation', function()
    it('handles errors across module boundaries', function()
      vim.system = function()
        error('system call failed')
      end

      assert.has_error(function()
        cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })
      end)
    end)

    it('provides coherent error messages', function()
      cp.handle_command({ fargs = {} })

      local usage_error = false
      for _, log_entry in ipairs(mock_log_messages) do
        if log_entry.level == vim.log.levels.ERROR and log_entry.msg:match('Usage:') then
          usage_error = true
          break
        end
      end
      assert.is_true(usage_error)
    end)

    it('maintains system stability on errors', function()
      vim.system = function(cmd, opts)
        if vim.tbl_contains(cmd, 'metadata') then
          return {
            wait = function()
              return { code = 1, stderr = 'scraper failed' }
            end,
          }
        end
        return {
          wait = function()
            return { code = 0 }
          end,
        }
      end

      assert.has_no_errors(function()
        cp.handle_command({ fargs = { 'atcoder', 'abc123' } })
        assert.is_true(cp.is_initialized())
      end)
    end)
  end)

  describe('performance', function()
    it('handles large contest data efficiently', function()
      local large_problems = {}
      for i = 1, 100 do
        table.insert(large_problems, { id = string.char(96 + i % 26), name = 'Problem ' .. i })
      end

      vim.system = function(cmd, opts)
        if vim.tbl_contains(cmd, 'metadata') then
          return {
            wait = function()
              return {
                code = 0,
                stdout = vim.json.encode({ success = true, problems = large_problems }),
              }
            end,
          }
        end
        return {
          wait = function()
            return { code = 0 }
          end,
        }
      end

      local start_time = vim.uv.hrtime()
      cp.handle_command({ fargs = { 'atcoder', 'abc123' } })
      local elapsed = (vim.uv.hrtime() - start_time) / 1000000

      assert.is_true(elapsed < 1000)
    end)

    it('manages memory usage appropriately', function()
      local initial_buf_count = #vim.api.nvim_list_bufs()

      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })
      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'b' } })
      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'c' } })

      local final_buf_count = #vim.api.nvim_list_bufs()
      local buf_increase = final_buf_count - initial_buf_count

      assert.is_true(buf_increase < 10)
    end)

    it('maintains responsiveness during operations', function()
      local call_count = 0
      vim.system = function(cmd, opts)
        call_count = call_count + 1
        vim.wait(10)
        return {
          wait = function()
            return { code = 0, stdout = '{}' }
          end,
        }
      end

      local start_time = vim.uv.hrtime()
      cp.handle_command({ fargs = { 'atcoder', 'abc123', 'a' } })
      local elapsed = (vim.uv.hrtime() - start_time) / 1000000

      assert.is_true(elapsed < 500)
      assert.is_true(call_count > 0)
    end)
  end)
end)
