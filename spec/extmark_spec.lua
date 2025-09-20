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
    it('clears namespace when buffer is deleted', function()
      local bufnr = 1
      local namespace = 100
      local mock_clear = spy.on(vim.api, 'nvim_buf_clear_namespace')
      local mock_delete = stub(vim.api, 'nvim_buf_delete')

      mock_delete.returns(true)

      highlight.apply_highlights(bufnr, {
        {
          line = 0,
          col_start = 0,
          col_end = 5,
          highlight_group = 'CpDiffAdded',
        },
      }, namespace)

      vim.api.nvim_buf_delete(bufnr, { force = true })

      assert.spy(mock_clear).was_called_with(bufnr, namespace, 0, -1)
      mock_clear:revert()
      mock_delete:revert()
    end)

    it('handles buffer deletion failure', function()
      local bufnr = 1
      local namespace = 100
      local mock_clear = spy.on(vim.api, 'nvim_buf_clear_namespace')
      local mock_delete = stub(vim.api, 'nvim_buf_delete')

      mock_delete.throws('Buffer deletion failed')

      highlight.apply_highlights(bufnr, {
        {
          line = 0,
          col_start = 0,
          col_end = 5,
          highlight_group = 'CpDiffAdded',
        },
      }, namespace)

      local success = pcall(vim.api.nvim_buf_delete, bufnr, { force = true })

      assert.is_false(success)
      assert.spy(mock_clear).was_called_with(bufnr, namespace, 0, -1)

      mock_clear:revert()
      mock_delete:revert()
    end)

    it('handles invalid buffer', function()
      local bufnr = 999
      local namespace = 100
      local mock_clear = spy.on(vim.api, 'nvim_buf_clear_namespace')
      local mock_extmark = spy.on(vim.api, 'nvim_buf_set_extmark')

      mock_clear.throws('Invalid buffer')
      mock_extmark.throws('Invalid buffer')

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

    it('clears specific namespace without affecting others', function()
      local bufnr = 1
      local ns1 = 100
      local ns2 = 200
      local mock_clear = spy.on(vim.api, 'nvim_buf_clear_namespace')

      highlight.apply_highlights(bufnr, {
        { line = 0, col_start = 0, col_end = 5, highlight_group = 'CpDiffAdded' },
      }, ns1)

      highlight.apply_highlights(bufnr, {
        { line = 1, col_start = 0, col_end = 3, highlight_group = 'CpDiffRemoved' },
      }, ns2)

      assert.spy(mock_clear).was_called_with(bufnr, ns1, 0, -1)
      assert.spy(mock_clear).was_called_with(bufnr, ns2, 0, -1)
      assert.spy(mock_clear).was_called(2)

      mock_clear:revert()
    end)
  end)

  describe('multiple updates', function()
    it('clears previous extmarks on each update', function()
      local bufnr = 1
      local namespace = 100
      local mock_clear = spy.on(vim.api, 'nvim_buf_clear_namespace')
      local mock_extmark = spy.on(vim.api, 'nvim_buf_set_extmark')

      highlight.apply_highlights(bufnr, {
        { line = 0, col_start = 0, col_end = 5, highlight_group = 'CpDiffAdded' },
      }, namespace)

      highlight.apply_highlights(bufnr, {
        { line = 1, col_start = 0, col_end = 3, highlight_group = 'CpDiffRemoved' },
      }, namespace)

      highlight.apply_highlights(bufnr, {
        { line = 2, col_start = 0, col_end = 7, highlight_group = 'CpDiffAdded' },
      }, namespace)

      assert.spy(mock_clear).was_called(3)
      assert.spy(mock_clear).was_called_with(bufnr, namespace, 0, -1)
      assert.spy(mock_extmark).was_called(3)

      mock_clear:revert()
      mock_extmark:revert()
    end)

    it('handles empty highlights', function()
      local bufnr = 1
      local namespace = 100
      local mock_clear = spy.on(vim.api, 'nvim_buf_clear_namespace')
      local mock_extmark = spy.on(vim.api, 'nvim_buf_set_extmark')

      highlight.apply_highlights(bufnr, {
        { line = 0, col_start = 0, col_end = 5, highlight_group = 'CpDiffAdded' },
      }, namespace)

      highlight.apply_highlights(bufnr, {}, namespace)

      assert.spy(mock_clear).was_called(2)
      assert.spy(mock_extmark).was_called(1)

      mock_clear:revert()
      mock_extmark:revert()
    end)

    it('skips invalid highlights', function()
      local bufnr = 1
      local namespace = 100
      local mock_clear = spy.on(vim.api, 'nvim_buf_clear_namespace')
      local mock_extmark = spy.on(vim.api, 'nvim_buf_set_extmark')

      highlight.apply_highlights(bufnr, {
        { line = 0, col_start = 5, col_end = 5, highlight_group = 'CpDiffAdded' },
        { line = 1, col_start = 7, col_end = 3, highlight_group = 'CpDiffAdded' },
        { line = 2, col_start = 0, col_end = 5, highlight_group = 'CpDiffAdded' },
      }, namespace)

      assert.spy(mock_clear).was_called_with(bufnr, namespace, 0, -1)
      assert.spy(mock_extmark).was_called(1)
      assert.spy(mock_extmark).was_called_with(bufnr, namespace, 2, 0, {
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
      local mock_extmark = spy.on(vim.api, 'nvim_buf_set_extmark')

      mock_clear.throws('Namespace clear failed')

      local success = pcall(highlight.apply_highlights, bufnr, {
        { line = 0, col_start = 0, col_end = 5, highlight_group = 'CpDiffAdded' },
      }, namespace)

      assert.is_false(success)
      assert.spy(mock_extmark).was_not_called()

      mock_clear:revert()
      mock_extmark:revert()
    end)

    it('fails when extmark creation fails', function()
      local bufnr = 1
      local namespace = 100
      local mock_clear = spy.on(vim.api, 'nvim_buf_clear_namespace')
      local mock_extmark = stub(vim.api, 'nvim_buf_set_extmark')

      mock_extmark.throws('Extmark failed')

      local success = pcall(highlight.apply_highlights, bufnr, {
        { line = 0, col_start = 0, col_end = 5, highlight_group = 'CpDiffAdded' },
      }, namespace)

      assert.spy(mock_clear).was_called_with(bufnr, namespace, 0, -1)
      assert.is_false(success)

      mock_clear:revert()
      mock_extmark:revert()
    end)
  end)

  describe('buffer lifecycle', function()
    it('manages extmarks through full lifecycle', function()
      local mock_create_buf = stub(vim.api, 'nvim_create_buf')
      local mock_delete_buf = stub(vim.api, 'nvim_buf_delete')
      local mock_clear = spy.on(vim.api, 'nvim_buf_clear_namespace')
      local mock_extmark = spy.on(vim.api, 'nvim_buf_set_extmark')

      local bufnr = 42
      local namespace = 100

      mock_create_buf.returns(bufnr)
      mock_delete_buf.returns(true)

      local buf = vim.api.nvim_create_buf(false, true)
      assert.equals(bufnr, buf)

      highlight.apply_highlights(bufnr, {
        { line = 0, col_start = 0, col_end = 5, highlight_group = 'CpDiffAdded' },
      }, namespace)

      highlight.apply_highlights(bufnr, {
        { line = 1, col_start = 0, col_end = 3, highlight_group = 'CpDiffRemoved' },
      }, namespace)

      vim.api.nvim_buf_delete(bufnr, { force = true })

      assert.spy(mock_clear).was_called(2)
      assert.spy(mock_extmark).was_called(2)
      assert.stub(mock_delete_buf).was_called_with(bufnr, { force = true })

      mock_create_buf:revert()
      mock_delete_buf:revert()
      mock_clear:revert()
      mock_extmark:revert()
    end)
  end)
end)
