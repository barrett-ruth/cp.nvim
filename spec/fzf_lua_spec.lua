describe('cp.fzf_lua', function()
  local spec_helper = require('spec.spec_helper')

  before_each(function()
    spec_helper.setup()

    package.preload['fzf-lua'] = function()
      return {
        fzf_exec = function(_, _) end,
      }
    end
  end)

  after_each(function()
    spec_helper.teardown()
  end)

  describe('module loading', function()
    it('loads fzf-lua integration without error', function()
      assert.has_no.errors(function()
        require('cp.pickers.fzf_lua')
      end)
    end)

    it('returns module with picker function', function()
      local fzf_lua_cp = require('cp.pickers.fzf_lua')
      assert.is_table(fzf_lua_cp)
      assert.is_function(fzf_lua_cp.pick)
    end)
  end)
end)
