describe('cp.snippets', function()
  local snippets
  local mock_luasnip
  local spec_helper = require('spec.spec_helper')

  before_each(function()
    spec_helper.setup()
    package.loaded['cp.snippets'] = nil
    snippets = require('cp.snippets')
    mock_luasnip = {
      snippet = function(trigger, body)
        return { trigger = trigger, body = body }
      end,
      insert_node = function(pos)
        return { type = 'insert', pos = pos }
      end,
      add_snippets = function(filetype, snippet_list)
        mock_luasnip.added = mock_luasnip.added or {}
        mock_luasnip.added[filetype] = snippet_list
      end,
      added = {},
    }

    mock_luasnip.extras = {
      fmt = {
        fmt = function(template, nodes)
          return { template = template, nodes = nodes }
        end,
      },
    }

    package.loaded['luasnip'] = mock_luasnip
    package.loaded['luasnip.extras.fmt'] = mock_luasnip.extras.fmt
  end)

  after_each(function()
    spec_helper.teardown()
    package.loaded['cp.snippets'] = nil
    package.loaded['luasnip'] = nil
    package.loaded['luasnip.extras.fmt'] = nil
  end)

  describe('setup without luasnip', function()
    it('handles missing luasnip gracefully', function()
      package.loaded['luasnip'] = nil

      assert.has_no_errors(function()
        snippets.setup({})
      end)
    end)
  end)

  describe('setup with luasnip available', function()
    it('sets up default cpp snippets for all contests', function()
      local config = { snippets = {} }

      snippets.setup(config)

      assert.is_not_nil(mock_luasnip.added.cpp)
      assert.is_true(#mock_luasnip.added.cpp >= 3)

      local triggers = {}
      for _, snippet in ipairs(mock_luasnip.added.cpp) do
        table.insert(triggers, snippet.trigger)
      end

      assert.is_true(vim.tbl_contains(triggers, 'cp.nvim/codeforces.cpp'))
      assert.is_true(vim.tbl_contains(triggers, 'cp.nvim/atcoder.cpp'))
      assert.is_true(vim.tbl_contains(triggers, 'cp.nvim/cses.cpp'))
    end)

    it('sets up default python snippets for all contests', function()
      local config = { snippets = {} }

      snippets.setup(config)

      assert.is_not_nil(mock_luasnip.added.python)
      assert.is_true(#mock_luasnip.added.python >= 3)

      local triggers = {}
      for _, snippet in ipairs(mock_luasnip.added.python) do
        table.insert(triggers, snippet.trigger)
      end

      assert.is_true(vim.tbl_contains(triggers, 'cp.nvim/codeforces.python'))
      assert.is_true(vim.tbl_contains(triggers, 'cp.nvim/atcoder.python'))
      assert.is_true(vim.tbl_contains(triggers, 'cp.nvim/cses.python'))
    end)

    it('includes template content with placeholders', function()
      local config = { snippets = {} }

      snippets.setup(config)

      local cpp_snippets = mock_luasnip.added.cpp or {}
      local codeforces_snippet = nil
      for _, snippet in ipairs(cpp_snippets) do
        if snippet.trigger == 'cp.nvim/codeforces.cpp' then
          codeforces_snippet = snippet
          break
        end
      end

      assert.is_not_nil(codeforces_snippet)
      assert.is_not_nil(codeforces_snippet.body)
      assert.equals('table', type(codeforces_snippet.body))
      assert.is_not_nil(codeforces_snippet.body.template:match('#include'))
      assert.is_not_nil(codeforces_snippet.body.template:match('void solve'))
    end)

    it('respects user snippet overrides', function()
      local custom_snippet = {
        trigger = 'cp.nvim/custom.cpp',
        body = 'custom template',
      }
      local config = {
        snippets = { custom_snippet },
      }

      snippets.setup(config)

      local cpp_snippets = mock_luasnip.added.cpp or {}
      local found_custom = false
      for _, snippet in ipairs(cpp_snippets) do
        if snippet.trigger == 'cp.nvim/custom.cpp' then
          found_custom = true
          assert.equals('custom template', snippet.body)
          break
        end
      end
      assert.is_true(found_custom)
    end)

    it('filters user snippets by language', function()
      local cpp_snippet = {
        trigger = 'cp.nvim/custom.cpp',
        body = 'cpp template',
      }
      local python_snippet = {
        trigger = 'cp.nvim/custom.python',
        body = 'python template',
      }
      local config = {
        snippets = { cpp_snippet, python_snippet },
      }

      snippets.setup(config)

      local cpp_snippets = mock_luasnip.added.cpp or {}
      local python_snippets = mock_luasnip.added.python or {}

      local cpp_has_custom = false
      for _, snippet in ipairs(cpp_snippets) do
        if snippet.trigger == 'cp.nvim/custom.cpp' then
          cpp_has_custom = true
          break
        end
      end

      local python_has_custom = false
      for _, snippet in ipairs(python_snippets) do
        if snippet.trigger == 'cp.nvim/custom.python' then
          python_has_custom = true
          break
        end
      end

      assert.is_true(cpp_has_custom)
      assert.is_true(python_has_custom)
    end)

    it('handles empty config gracefully', function()
      assert.has_no_errors(function()
        snippets.setup({})
      end)

      assert.is_not_nil(mock_luasnip.added.cpp)
      assert.is_not_nil(mock_luasnip.added.python)
    end)

    it('handles empty config gracefully', function()
      assert.has_no_errors(function()
        snippets.setup({ snippets = {} })
      end)
    end)

    it('creates templates for correct filetypes', function()
      local config = { snippets = {} }

      snippets.setup(config)

      assert.is_not_nil(mock_luasnip.added.cpp)
      assert.is_not_nil(mock_luasnip.added.python)
      assert.is_nil(mock_luasnip.added.c)
      assert.is_nil(mock_luasnip.added.py)
    end)

    it('excludes overridden default snippets', function()
      local override_snippet = {
        trigger = 'cp.nvim/codeforces.cpp',
        body = 'overridden template',
      }
      local config = {
        snippets = { override_snippet },
      }

      snippets.setup(config)

      local cpp_snippets = mock_luasnip.added.cpp or {}
      local codeforces_count = 0
      for _, snippet in ipairs(cpp_snippets) do
        if snippet.trigger == 'cp.nvim/codeforces.cpp' then
          codeforces_count = codeforces_count + 1
        end
      end

      assert.equals(1, codeforces_count)
    end)

    it('handles case-insensitive snippet triggers', function()
      local mixed_case_snippet = {
        trigger = 'cp.nvim/CodeForces.cpp',
        body = 'mixed case template',
      }
      local upper_case_snippet = {
        trigger = 'cp.nvim/ATCODER.cpp',
        body = 'upper case template',
      }
      local config = {
        snippets = { mixed_case_snippet, upper_case_snippet },
      }

      snippets.setup(config)

      local cpp_snippets = mock_luasnip.added.cpp or {}

      local has_mixed_case = false
      local has_upper_case = false
      local default_codeforces_count = 0
      local default_atcoder_count = 0

      for _, snippet in ipairs(cpp_snippets) do
        if snippet.trigger == 'cp.nvim/CodeForces.cpp' then
          has_mixed_case = true
          assert.equals('mixed case template', snippet.body)
        elseif snippet.trigger == 'cp.nvim/ATCODER.cpp' then
          has_upper_case = true
          assert.equals('upper case template', snippet.body)
        elseif snippet.trigger == 'cp.nvim/codeforces.cpp' then
          default_codeforces_count = default_codeforces_count + 1
        elseif snippet.trigger == 'cp.nvim/atcoder.cpp' then
          default_atcoder_count = default_atcoder_count + 1
        end
      end

      assert.is_true(has_mixed_case)
      assert.is_true(has_upper_case)
      assert.equals(0, default_codeforces_count, 'Default codeforces snippet should be overridden')
      assert.equals(0, default_atcoder_count, 'Default atcoder snippet should be overridden')
    end)
  end)
end)
