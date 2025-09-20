describe('cp.run_render', function()
  local run_render = require('cp.run_render')
  local spec_helper = require('spec.spec_helper')

  before_each(function()
    spec_helper.setup()
  end)

  after_each(function()
    spec_helper.teardown()
  end)

  describe('get_status_info', function()
    it('returns AC for pass status', function()
      local test_case = { status = 'pass' }
      local result = run_render.get_status_info(test_case)
      assert.equals('AC', result.text)
      assert.equals('CpTestAC', result.highlight_group)
    end)

    it('returns WA for fail status with normal exit codes', function()
      local test_case = { status = 'fail', code = 1 }
      local result = run_render.get_status_info(test_case)
      assert.equals('WA', result.text)
      assert.equals('CpTestWA', result.highlight_group)
    end)

    it('returns TLE for timeout status', function()
      local test_case = { status = 'timeout' }
      local result = run_render.get_status_info(test_case)
      assert.equals('TLE', result.text)
      assert.equals('CpTestTLE', result.highlight_group)
    end)

    it('returns TLE for timed out fail status', function()
      local test_case = { status = 'fail', timed_out = true }
      local result = run_render.get_status_info(test_case)
      assert.equals('TLE', result.text)
      assert.equals('CpTestTLE', result.highlight_group)
    end)

    it('returns RTE for fail with signal codes (>= 128)', function()
      local test_case = { status = 'fail', code = 139 }
      local result = run_render.get_status_info(test_case)
      assert.equals('RTE', result.text)
      assert.equals('CpTestRTE', result.highlight_group)
    end)

    it('returns empty for pending status', function()
      local test_case = { status = 'pending' }
      local result = run_render.get_status_info(test_case)
      assert.equals('', result.text)
      assert.equals('CpTestPending', result.highlight_group)
    end)

    it('returns running indicator for running status', function()
      local test_case = { status = 'running' }
      local result = run_render.get_status_info(test_case)
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
      local result = run_render.render_test_list(test_state)
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
      local result = run_render.render_test_list(test_state)
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
      local result = run_render.render_test_list(test_state)
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
      local result = run_render.render_test_list(test_state)
      assert.equals(3, #result)
    end)

    it('preserves input line breaks', function()
      local test_state = {
        test_cases = {
          { status = 'pass', input = '5\n3\n1' },
        },
        current_index = 1,
      }
      local result = run_render.render_test_list(test_state)
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
      local result = run_render.render_status_bar(test_case)
      assert.equals('45.70ms │ Exit: 0', result)
    end)

    it('handles missing time', function()
      local test_case = { code = 0 }
      local result = run_render.render_status_bar(test_case)
      assert.equals('Exit: 0', result)
    end)

    it('handles missing exit code', function()
      local test_case = { time_ms = 123 }
      local result = run_render.render_status_bar(test_case)
      assert.equals('123.00ms', result)
    end)

    it('returns empty for nil test case', function()
      local result = run_render.render_status_bar(nil)
      assert.equals('', result)
    end)
  end)

  describe('setup_highlights', function()
    it('sets up all highlight groups', function()
      local mock_set_hl = spy.on(vim.api, 'nvim_set_hl')
      run_render.setup_highlights()

      assert.spy(mock_set_hl).was_called(7)
      assert.spy(mock_set_hl).was_called_with(0, 'CpTestAC', { fg = '#10b981' })
      assert.spy(mock_set_hl).was_called_with(0, 'CpTestWA', { fg = '#ef4444' })
      assert.spy(mock_set_hl).was_called_with(0, 'CpTestTLE', { fg = '#f59e0b' })
      assert.spy(mock_set_hl).was_called_with(0, 'CpTestRTE', { fg = '#8b5cf6' })

      mock_set_hl:revert()
    end)
  end)

  describe('highlight positioning', function()
    it('generates correct highlight positions for status text', function()
      local test_state = {
        test_cases = {
          { status = 'pass', input = '' },
          { status = 'fail', code = 1, input = '' },
        },
        current_index = 1,
      }
      local lines, highlights = run_render.render_test_list(test_state)

      assert.equals(2, #highlights)

      for _, hl in ipairs(highlights) do
        assert.is_not_nil(hl.line)
        assert.is_not_nil(hl.col_start)
        assert.is_not_nil(hl.col_end)
        assert.is_not_nil(hl.highlight_group)
        assert.is_true(hl.col_end > hl.col_start)

        local line_content = lines[hl.line + 1]
        local highlighted_text = line_content:sub(hl.col_start + 1, hl.col_end)
        assert.is_true(highlighted_text == 'AC' or highlighted_text == 'WA')
      end
    end)
  end)
end)
