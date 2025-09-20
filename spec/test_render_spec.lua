describe('cp.test_render', function()
  local test_render = require('cp.test_render')

  describe('get_status_info', function()
    it('returns AC for pass status', function()
      local test_case = { status = 'pass' }
      local result = test_render.get_status_info(test_case)
      assert.equals('AC', result.text)
      assert.equals('CpTestAC', result.highlight_group)
    end)

    it('returns WA for fail status with normal exit codes', function()
      local test_case = { status = 'fail', code = 1 }
      local result = test_render.get_status_info(test_case)
      assert.equals('WA', result.text)
      assert.equals('CpTestError', result.highlight_group)
    end)

    it('returns TLE for timeout status', function()
      local test_case = { status = 'timeout' }
      local result = test_render.get_status_info(test_case)
      assert.equals('TLE', result.text)
      assert.equals('CpTestError', result.highlight_group)
    end)

    it('returns TLE for timed out fail status', function()
      local test_case = { status = 'fail', timed_out = true }
      local result = test_render.get_status_info(test_case)
      assert.equals('TLE', result.text)
      assert.equals('CpTestError', result.highlight_group)
    end)

    it('returns RTE for fail with signal codes (>= 128)', function()
      local test_case = { status = 'fail', code = 139 }
      local result = test_render.get_status_info(test_case)
      assert.equals('RTE', result.text)
      assert.equals('CpTestError', result.highlight_group)
    end)

    it('returns empty for pending status', function()
      local test_case = { status = 'pending' }
      local result = test_render.get_status_info(test_case)
      assert.equals('', result.text)
      assert.equals('CpTestPending', result.highlight_group)
    end)

    it('returns running indicator for running status', function()
      local test_case = { status = 'running' }
      local result = test_render.get_status_info(test_case)
      assert.equals('...', result.text)
      assert.equals('CpTestPending', result.highlight_group)
    end)
  end)

  describe('render_test_list', function()
    it('renders table with headers and borders', function()
      local test_state = {
        test_cases = {
          { status = 'pass', input = '5' },
          { status = 'fail', code = 1, input = '3' },
        },
        current_index = 1,
      }
      local result = test_render.render_test_list(test_state)
      assert.is_true(result[1]:find('^┌') ~= nil)
      assert.is_true(result[2]:find('│.*#.*│.*Status.*│.*Time.*│.*Exit Code.*│') ~= nil)
      assert.is_true(result[3]:find('^├') ~= nil)
    end)

    it('shows current test with > prefix in table', function()
      local test_state = {
        test_cases = {
          { status = 'pass', input = '' },
          { status = 'pass', input = '' },
        },
        current_index = 2,
      }
      local result = test_render.render_test_list(test_state)
      local found_current = false
      for _, line in ipairs(result) do
        if line:match('│.*> 2.*│') then
          found_current = true
          break
        end
      end
      assert.is_true(found_current)
    end)

    it('displays input only for current test', function()
      local test_state = {
        test_cases = {
          { status = 'pass', input = '5 3' },
          { status = 'pass', input = '2 4' },
        },
        current_index = 1,
      }
      local result = test_render.render_test_list(test_state)
      local found_input = false
      for _, line in ipairs(result) do
        if line:match('│5 3') then
          found_input = true
          break
        end
      end
      assert.is_true(found_input)
    end)

    it('handles empty test cases', function()
      local test_state = { test_cases = {}, current_index = 1 }
      local result = test_render.render_test_list(test_state)
      assert.equals(3, #result)
    end)

    it('preserves input line breaks', function()
      local test_state = {
        test_cases = {
          { status = 'pass', input = '5\n3\n1' },
        },
        current_index = 1,
      }
      local result = test_render.render_test_list(test_state)
      local input_lines = {}
      for _, line in ipairs(result) do
        if line:match('^│[531]') then
          table.insert(input_lines, line:match('│([531])'))
        end
      end
      assert.same({ '5', '3', '1' }, input_lines)
    end)
  end)

  describe('render_status_bar', function()
    it('formats time and exit code', function()
      local test_case = { time_ms = 45.7, code = 0 }
      local result = test_render.render_status_bar(test_case)
      assert.equals('45.70ms │ Exit: 0', result)
    end)

    it('handles missing time', function()
      local test_case = { code = 0 }
      local result = test_render.render_status_bar(test_case)
      assert.equals('Exit: 0', result)
    end)

    it('handles missing exit code', function()
      local test_case = { time_ms = 123 }
      local result = test_render.render_status_bar(test_case)
      assert.equals('123.00ms', result)
    end)

    it('returns empty for nil test case', function()
      local result = test_render.render_status_bar(nil)
      assert.equals('', result)
    end)
  end)

  describe('setup_highlights', function()
    it('sets up all highlight groups', function()
      local mock_set_hl = spy.on(vim.api, 'nvim_set_hl')
      test_render.setup_highlights()

      assert.spy(mock_set_hl).was_called(5)
      assert.spy(mock_set_hl).was_called_with(0, 'CpTestAC', { fg = '#10b981', bold = true })
      assert.spy(mock_set_hl).was_called_with(0, 'CpTestError', { fg = '#ef4444', bold = true })

      mock_set_hl:revert()
    end)
  end)
end)
