describe('cp.highlight', function()
  local spec_helper = require('spec.spec_helper')
  local highlight

  before_each(function()
    spec_helper.setup()
    highlight = require('cp.ui.highlight')
  end)

  after_each(function()
    spec_helper.teardown()
  end)

  describe('parse_git_diff', function()
    it('skips git diff headers', function()
      local diff_output = [[diff --git a/test b/test
index 1234567..abcdefg 100644
--- a/test
+++ b/test
@@ -1,3 +1,3 @@
 hello
+world
-goodbye]]
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
    it('handles empty highlights without errors', function()
      assert.has_no_errors(function()
        highlight.apply_highlights(1, {}, 100)
      end)
    end)

    it('handles valid highlight data without errors', function()
      local highlights = {
        {
          line = 0,
          col_start = 5,
          col_end = 10,
          highlight_group = 'CpDiffAdded',
        },
      }
      assert.has_no_errors(function()
        highlight.apply_highlights(1, highlights, 100)
      end)
    end)
  end)

  describe('create_namespace', function()
    it('returns a number', function()
      local result = highlight.create_namespace()
      assert.equals('number', type(result))
    end)
  end)

  describe('parse_and_apply_diff', function()
    it('returns content lines', function()
      local result = highlight.parse_and_apply_diff(1, '+first\n+second', 100)
      assert.same({ 'first', 'second' }, result)
    end)

    it('handles empty diff', function()
      local result = highlight.parse_and_apply_diff(1, '', 100)
      assert.same({}, result)
    end)
  end)
end)
