describe('cp.highlight', function()
  local highlight = require('cp.highlight')

  describe('parse_git_diff', function()
    it('skips git diff headers', function()
      local diff_output = [[
diff --git a/test b/test
index 1234567..abcdefg 100644
--- a/test
+++ b/test
@@ -1,3 +1,3 @@
 hello
+world
-goodbye
]]
      local result = highlight.parse_git_diff(diff_output)
      assert.same({ 'hello', 'world' }, result.content)
    end)

    it('processes added lines', function()
      local diff_output = '+hello w{+o+}rld'
      local result = highlight.parse_git_diff(diff_output)
      assert.same({ 'hello world' }, result.content)
      assert.equals(1, #result.highlights)
      assert.equals('CpDiffAdded', result.highlights[1].highlight_group)
    end)

    it('ignores removed lines', function()
      local diff_output = 'hello\n-removed line\n+kept line'
      local result = highlight.parse_git_diff(diff_output)
      assert.same({ 'hello', 'kept line' }, result.content)
    end)

    it('handles unchanged lines', function()
      local diff_output = 'unchanged line\n+added line'
      local result = highlight.parse_git_diff(diff_output)
      assert.same({ 'unchanged line', 'added line' }, result.content)
    end)

    it('sets correct line numbers', function()
      local diff_output = '+first {+added+}\n+second {+text+}'
      local result = highlight.parse_git_diff(diff_output)
      assert.equals(0, result.highlights[1].line)
      assert.equals(1, result.highlights[2].line)
    end)

    it('handles empty diff output', function()
      local result = highlight.parse_git_diff('')
      assert.same({}, result.content)
      assert.same({}, result.highlights)
    end)
  end)

  describe('apply_highlights', function()
    it('clears existing highlights', function()
      local mock_clear = spy.on(vim.api, 'nvim_buf_clear_namespace')
      local bufnr = 1
      local namespace = 100

      highlight.apply_highlights(bufnr, {}, namespace)

      assert.spy(mock_clear).was_called_with(bufnr, namespace, 0, -1)
      mock_clear:revert()
    end)

    it('applies extmarks with correct positions', function()
      local mock_extmark = spy.on(vim.api, 'nvim_buf_set_extmark')
      local bufnr = 1
      local namespace = 100
      local highlights = {
        {
          line = 0,
          col_start = 5,
          col_end = 10,
          highlight_group = 'CpDiffAdded',
        },
      }

      highlight.apply_highlights(bufnr, highlights, namespace)

      assert.spy(mock_extmark).was_called_with(bufnr, namespace, 0, 5, {
        end_col = 10,
        hl_group = 'CpDiffAdded',
        priority = 100,
      })
      mock_extmark:revert()
    end)

    it('uses correct highlight groups', function()
      local mock_extmark = spy.on(vim.api, 'nvim_buf_set_extmark')
      local highlights = {
        {
          line = 0,
          col_start = 0,
          col_end = 5,
          highlight_group = 'CpDiffAdded',
        },
      }

      highlight.apply_highlights(1, highlights, 100)

      local call_args = mock_extmark.calls[1].vals
      assert.equals('CpDiffAdded', call_args[4].hl_group)
      mock_extmark:revert()
    end)

    it('handles empty highlights', function()
      local mock_extmark = spy.on(vim.api, 'nvim_buf_set_extmark')

      highlight.apply_highlights(1, {}, 100)

      assert.spy(mock_extmark).was_not_called()
      mock_extmark:revert()
    end)
  end)

  describe('create_namespace', function()
    it('creates unique namespace', function()
      local mock_create = stub(vim.api, 'nvim_create_namespace')
      mock_create.returns(42)

      local result = highlight.create_namespace()

      assert.equals(42, result)
      assert.stub(mock_create).was_called_with('cp_diff_highlights')
      mock_create:revert()
    end)
  end)

  describe('parse_and_apply_diff', function()
    it('parses diff and applies to buffer', function()
      local mock_set_lines = spy.on(vim.api, 'nvim_buf_set_lines')
      local mock_apply = spy.on(highlight, 'apply_highlights')
      local bufnr = 1
      local namespace = 100
      local diff_output = '+hello {+world+}'

      local result = highlight.parse_and_apply_diff(bufnr, diff_output, namespace)

      assert.same({ 'hello world' }, result)
      assert.spy(mock_set_lines).was_called_with(bufnr, 0, -1, false, { 'hello world' })
      assert.spy(mock_apply).was_called()

      mock_set_lines:revert()
      mock_apply:revert()
    end)

    it('sets buffer content', function()
      local mock_set_lines = spy.on(vim.api, 'nvim_buf_set_lines')

      highlight.parse_and_apply_diff(1, '+test line', 100)

      assert.spy(mock_set_lines).was_called_with(1, 0, -1, false, { 'test line' })
      mock_set_lines:revert()
    end)

    it('applies highlights', function()
      local mock_apply = spy.on(highlight, 'apply_highlights')

      highlight.parse_and_apply_diff(1, '+hello {+world+}', 100)

      assert.spy(mock_apply).was_called()
      mock_apply:revert()
    end)

    it('returns content lines', function()
      local result = highlight.parse_and_apply_diff(1, '+first\n+second', 100)
      assert.same({ 'first', 'second' }, result)
    end)
  end)
end)
