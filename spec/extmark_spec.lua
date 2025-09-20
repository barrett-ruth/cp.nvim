describe('extmarks', function()
  local spec_helper = require('spec.spec_helper')
  local highlight

  before_each(function()
    spec_helper.setup()
    highlight = require('cp.highlight')
  end)

  after_each(function()
    spec_helper.teardown()
  end)

  describe('buffer deletion', function()
    it('clears namespace on buffer delete', function()
      local bufnr = 1
      local namespace = 100
      local mock_clear = stub(vim.api, 'nvim_buf_clear_namespace')
      local mock_extmark = stub(vim.api, 'nvim_buf_set_extmark')

      highlight.apply_highlights(bufnr, {
        {
          line = 0,
          col_start = 0,
          col_end = 5,
          highlight_group = 'CpDiffAdded',
        },
      }, namespace)

      assert.stub(mock_clear).was_called_with(bufnr, namespace, 0, -1)
      mock_clear:revert()
      mock_extmark:revert()
    end)

    it('handles invalid buffer gracefully', function()
      local bufnr = 999
      local namespace = 100
      local mock_clear = stub(vim.api, 'nvim_buf_clear_namespace')
      local mock_extmark = stub(vim.api, 'nvim_buf_set_extmark')

      mock_clear.on_call_with(bufnr, namespace, 0, -1).invokes(function()
        error('Invalid buffer')
      end)

      local success = pcall(highlight.apply_highlights, bufnr, {
        {
          line = 0,
          col_start = 0,
          col_end = 5,
          highlight_group = 'CpDiffAdded',
        },
      }, namespace)

      assert.is_false(success)
      mock_clear:revert()
      mock_extmark:revert()
    end)
  end)

  describe('namespace isolation', function()
    it('creates unique namespaces', function()
      local mock_create = stub(vim.api, 'nvim_create_namespace')
      mock_create.on_call_with('cp_diff_highlights').returns(100)
      mock_create.on_call_with('cp_test_list').returns(200)
      mock_create.on_call_with('cp_ansi_highlights').returns(300)

      local diff_ns = highlight.create_namespace()
      local test_ns = vim.api.nvim_create_namespace('cp_test_list')
      local ansi_ns = vim.api.nvim_create_namespace('cp_ansi_highlights')

      assert.equals(100, diff_ns)
      assert.equals(200, test_ns)
      assert.equals(300, ansi_ns)

      mock_create:revert()
    end)

    it('clears specific namespace independently', function()
      local bufnr = 1
      local ns1 = 100
      local ns2 = 200
      local mock_clear = stub(vim.api, 'nvim_buf_clear_namespace')
      local mock_extmark = stub(vim.api, 'nvim_buf_set_extmark')

      highlight.apply_highlights(bufnr, {
        { line = 0, col_start = 0, col_end = 5, highlight_group = 'CpDiffAdded' },
      }, ns1)

      highlight.apply_highlights(bufnr, {
        { line = 1, col_start = 0, col_end = 3, highlight_group = 'CpDiffRemoved' },
      }, ns2)

      assert.stub(mock_clear).was_called_with(bufnr, ns1, 0, -1)
      assert.stub(mock_clear).was_called_with(bufnr, ns2, 0, -1)
      assert.stub(mock_clear).was_called(2)

      mock_clear:revert()
      mock_extmark:revert()
    end)
  end)

  describe('multiple updates', function()
    it('clears previous extmarks on each update', function()
      local bufnr = 1
      local namespace = 100
      local mock_clear = stub(vim.api, 'nvim_buf_clear_namespace')
      local mock_extmark = stub(vim.api, 'nvim_buf_set_extmark')

      highlight.apply_highlights(bufnr, {
        { line = 0, col_start = 0, col_end = 5, highlight_group = 'CpDiffAdded' },
      }, namespace)

      highlight.apply_highlights(bufnr, {
        { line = 1, col_start = 0, col_end = 3, highlight_group = 'CpDiffRemoved' },
      }, namespace)

      assert.stub(mock_clear).was_called(2)
      assert.stub(mock_clear).was_called_with(bufnr, namespace, 0, -1)
      assert.stub(mock_extmark).was_called(2)

      mock_clear:revert()
      mock_extmark:revert()
    end)

    it('handles empty highlights', function()
      local bufnr = 1
      local namespace = 100
      local mock_clear = stub(vim.api, 'nvim_buf_clear_namespace')
      local mock_extmark = stub(vim.api, 'nvim_buf_set_extmark')

      highlight.apply_highlights(bufnr, {
        { line = 0, col_start = 0, col_end = 5, highlight_group = 'CpDiffAdded' },
      }, namespace)

      highlight.apply_highlights(bufnr, {}, namespace)

      assert.stub(mock_clear).was_called(2)
      assert.stub(mock_extmark).was_called(1)

      mock_clear:revert()
      mock_extmark:revert()
    end)

    it('skips invalid highlights', function()
      local bufnr = 1
      local namespace = 100
      local mock_clear = stub(vim.api, 'nvim_buf_clear_namespace')
      local mock_extmark = stub(vim.api, 'nvim_buf_set_extmark')

      highlight.apply_highlights(bufnr, {
        { line = 0, col_start = 5, col_end = 5, highlight_group = 'CpDiffAdded' },
        { line = 1, col_start = 7, col_end = 3, highlight_group = 'CpDiffAdded' },
        { line = 2, col_start = 0, col_end = 5, highlight_group = 'CpDiffAdded' },
      }, namespace)

      assert.stub(mock_clear).was_called_with(bufnr, namespace, 0, -1)
      assert.stub(mock_extmark).was_called(1)
      assert.stub(mock_extmark).was_called_with(bufnr, namespace, 2, 0, {
        end_col = 5,
        hl_group = 'CpDiffAdded',
        priority = 100,
      })

      mock_clear:revert()
      mock_extmark:revert()
    end)
  end)

  describe('error handling', function()
    it('fails when clear_namespace fails', function()
      local bufnr = 1
      local namespace = 100
      local mock_clear = stub(vim.api, 'nvim_buf_clear_namespace')
      local mock_extmark = stub(vim.api, 'nvim_buf_set_extmark')

      mock_clear.on_call_with(bufnr, namespace, 0, -1).invokes(function()
        error('Namespace clear failed')
      end)

      local success = pcall(highlight.apply_highlights, bufnr, {
        { line = 0, col_start = 0, col_end = 5, highlight_group = 'CpDiffAdded' },
      }, namespace)

      assert.is_false(success)
      assert.stub(mock_extmark).was_not_called()

      mock_clear:revert()
      mock_extmark:revert()
    end)
  end)

  describe('parse_and_apply_diff cleanup', function()
    it('clears namespace before applying parsed diff', function()
      local bufnr = 1
      local namespace = 100
      local mock_clear = stub(vim.api, 'nvim_buf_clear_namespace')
      local mock_extmark = stub(vim.api, 'nvim_buf_set_extmark')
      local mock_set_lines = stub(vim.api, 'nvim_buf_set_lines')
      local mock_get_option = stub(vim.api, 'nvim_get_option_value')
      local mock_set_option = stub(vim.api, 'nvim_set_option_value')

      mock_get_option.returns(false)

      highlight.parse_and_apply_diff(bufnr, '+hello {+world+}', namespace)

      assert.stub(mock_clear).was_called_with(bufnr, namespace, 0, -1)

      mock_clear:revert()
      mock_extmark:revert()
      mock_set_lines:revert()
      mock_get_option:revert()
      mock_set_option:revert()
    end)
  end)
end)
