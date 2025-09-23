describe('cp.diff', function()
  local spec_helper = require('spec.spec_helper')
  local diff

  before_each(function()
    spec_helper.setup()
    diff = require('cp.ui.diff')
  end)

  after_each(function()
    spec_helper.teardown()
  end)

  describe('get_available_backends', function()
    it('returns none, vim and git backends', function()
      local backends = diff.get_available_backends()
      table.sort(backends)
      assert.same({ 'git', 'none', 'vim' }, backends)
    end)
  end)

  describe('get_backend', function()
    it('returns vim backend by name', function()
      local backend = diff.get_backend('vim')
      assert.is_not_nil(backend)
      assert.equals('vim', backend.name)
    end)

    it('returns git backend by name', function()
      local backend = diff.get_backend('git')
      assert.is_not_nil(backend)
      assert.equals('git', backend.name)
    end)

    it('returns none backend by name', function()
      local backend = diff.get_backend('none')
      assert.is_not_nil(backend)
      assert.equals('none', backend.name)
    end)

    it('returns nil for invalid name', function()
      local backend = diff.get_backend('invalid')
      assert.is_nil(backend)
    end)
  end)

  describe('get_best_backend', function()
    it('defaults to vim backend', function()
      local backend = diff.get_best_backend()
      assert.equals('vim', backend.name)
    end)
  end)

  describe('none backend', function()
    it('returns both expected and actual content', function()
      local backend = diff.get_backend('none')
      local result = backend.render('expected\nline2', 'actual\nline2')

      assert.same({
        expected = { 'expected', 'line2' },
        actual = { 'actual', 'line2' },
      }, result.content)
      assert.same({}, result.highlights)
    end)
  end)

  describe('vim backend', function()
    it('returns content as-is', function()
      local backend = diff.get_backend('vim')
      local result = backend.render('expected', 'actual')

      assert.same({ 'actual' }, result.content)
      assert.is_nil(result.highlights)
    end)
  end)

  describe('is_git_available', function()
    it('returns boolean without errors', function()
      local result = diff.is_git_available()
      assert.equals('boolean', type(result))
    end)
  end)

  describe('render_diff', function()
    it('returns result without errors', function()
      assert.has_no_errors(function()
        diff.render_diff('expected', 'actual', 'vim')
      end)
    end)
  end)
end)
