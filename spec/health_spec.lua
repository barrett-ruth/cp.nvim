describe('cp.health', function()
  local health

  before_each(function()
    vim.fn = vim.tbl_extend('force', vim.fn, {
      executable = function()
        return 1
      end,
      filereadable = function()
        return 1
      end,
      has = function()
        return 1
      end,
      isdirectory = function()
        return 1
      end,
    })

    health = require('cp.health')
  end)

  describe('check function', function()
    it('runs without error', function()
      assert.has_no_errors(function()
        health.check()
      end)
    end)
  end)
end)
