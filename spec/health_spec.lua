describe('cp.health', function()
  local health

  before_each(function()
    local original_gsub = string.gsub
    string.gsub = original_gsub

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
      fnamemodify = function()
        return '/test/path'
      end,
    })

    vim.system = function()
      return {
        wait = function()
          return { code = 0, stdout = 'test version\n' }
        end,
      }
    end

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
