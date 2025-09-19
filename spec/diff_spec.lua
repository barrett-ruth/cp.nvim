describe('cp.diff', function()
  local diff = require('cp.diff')

  describe('get_available_backends', function()
    it('returns vim and git backends', function()
      local backends = diff.get_available_backends()
      table.sort(backends)
      assert.same({ 'git', 'vim' }, backends)
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

    it('returns nil for invalid name', function()
      local backend = diff.get_backend('invalid')
      assert.is_nil(backend)
    end)
  end)

  describe('is_git_available', function()
    it('returns true when git command succeeds', function()
      local mock_system = stub(vim, 'system')
      mock_system.returns({
        wait = function()
          return { code = 0 }
        end,
      })

      local result = diff.is_git_available()
      assert.is_true(result)

      mock_system:revert()
    end)

    it('returns false when git command fails', function()
      local mock_system = stub(vim, 'system')
      mock_system.returns({
        wait = function()
          return { code = 1 }
        end,
      })

      local result = diff.is_git_available()
      assert.is_false(result)

      mock_system:revert()
    end)
  end)

  describe('get_best_backend', function()
    it('returns preferred backend when available', function()
      local mock_is_available = stub(diff, 'is_git_available')
      mock_is_available.returns(true)

      local backend = diff.get_best_backend('git')
      assert.equals('git', backend.name)

      mock_is_available:revert()
    end)

    it('falls back to vim when git unavailable', function()
      local mock_is_available = stub(diff, 'is_git_available')
      mock_is_available.returns(false)

      local backend = diff.get_best_backend('git')
      assert.equals('vim', backend.name)

      mock_is_available:revert()
    end)

    it('defaults to vim backend', function()
      local backend = diff.get_best_backend()
      assert.equals('vim', backend.name)
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

  describe('git backend', function()
    it('creates temp files for diff', function()
      local mock_system = stub(vim, 'system')
      local mock_tempname = stub(vim.fn, 'tempname')
      local mock_writefile = stub(vim.fn, 'writefile')
      local mock_delete = stub(vim.fn, 'delete')

      mock_tempname.returns('/tmp/expected', '/tmp/actual')
      mock_system.returns({ wait = function() return { code = 1, stdout = 'diff output' } end })

      local backend = diff.get_backend('git')
      backend.render('expected text', 'actual text')

      assert.stub(mock_writefile).was_called(2)
      assert.stub(mock_delete).was_called(2)

      mock_system:revert()
      mock_tempname:revert()
      mock_writefile:revert()
      mock_delete:revert()
    end)

    it('returns raw diff output', function()
      local mock_system = stub(vim, 'system')
      local mock_tempname = stub(vim.fn, 'tempname')
      local mock_writefile = stub(vim.fn, 'writefile')
      local mock_delete = stub(vim.fn, 'delete')

      mock_tempname.returns('/tmp/expected', '/tmp/actual')
      mock_system.returns({ wait = function() return { code = 1, stdout = 'git diff output' } end })

      local backend = diff.get_backend('git')
      local result = backend.render('expected', 'actual')

      assert.equals('git diff output', result.raw_diff)

      mock_system:revert()
      mock_tempname:revert()
      mock_writefile:revert()
      mock_delete:revert()
    end)

    it('handles no differences', function()
      local mock_system = stub(vim, 'system')
      local mock_tempname = stub(vim.fn, 'tempname')
      local mock_writefile = stub(vim.fn, 'writefile')
      local mock_delete = stub(vim.fn, 'delete')

      mock_tempname.returns('/tmp/expected', '/tmp/actual')
      mock_system.returns({ wait = function() return { code = 0 } end })

      local backend = diff.get_backend('git')
      local result = backend.render('same', 'same')

      assert.same({ 'same' }, result.content)
      assert.same({}, result.highlights)

      mock_system:revert()
      mock_tempname:revert()
      mock_writefile:revert()
      mock_delete:revert()
    end)
  end)

  describe('render_diff', function()
    it('uses best available backend', function()
      local mock_backend = {
        render = function()
          return {}
        end,
      }
      local mock_get_best = stub(diff, 'get_best_backend')
      mock_get_best.returns(mock_backend)

      diff.render_diff('expected', 'actual', 'vim')

      assert.stub(mock_get_best).was_called_with('vim')
      mock_get_best:revert()
    end)
  end)
end)
