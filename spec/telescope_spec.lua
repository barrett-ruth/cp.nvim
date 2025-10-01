describe('cp.telescope', function()
  local spec_helper = require('spec.spec_helper')

  before_each(function()
    spec_helper.setup()

    package.preload['telescope'] = function()
      return {
        register_extension = function(ext_config)
          return ext_config
        end,
      }
    end

    package.preload['telescope.pickers'] = function()
      return {
        new = function(_, _)
          return {
            find = function() end,
          }
        end,
      }
    end

    package.preload['telescope.finders'] = function()
      return {
        new_table = function(opts)
          return opts
        end,
      }
    end

    package.preload['telescope.config'] = function()
      return {
        values = {
          generic_sorter = function()
            return {}
          end,
        },
      }
    end

    package.preload['telescope.actions'] = function()
      return {
        select_default = {
          replace = function() end,
        },
        close = function() end,
      }
    end

    package.preload['telescope.actions.state'] = function()
      return {
        get_selected_entry = function()
          return nil
        end,
      }
    end
  end)

  after_each(function()
    spec_helper.teardown()
  end)

  describe('module loading', function()
    it('registers telescope extension without error', function()
      assert.has_no_errors(function()
        require('cp.pickers.telescope')
      end)
    end)

    it('returns module with picker function', function()
      local telescope_cp = require('cp.pickers.telescope')
      assert.is_table(telescope_cp)
      assert.is_function(telescope_cp.pick)
    end)
  end)

  describe('basic running', function()
    it('can run and open the picker with :CP pick', function()
      local cp = require('cp')
      assert.has_no_errors(function()
        cp.handle_command({ fargs = { 'pick' } })
      end)
    end)
  end)
end)
