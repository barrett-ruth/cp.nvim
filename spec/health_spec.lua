describe('cp.health', function()
  local health
  local original_health = {}

  before_each(function()
    health = require('cp.health')
    original_health.start = vim.health.start
    original_health.ok = vim.health.ok
    original_health.warn = vim.health.warn
    original_health.error = vim.health.error
    original_health.info = vim.health.info
  end)

  after_each(function()
    vim.health = original_health
  end)

  describe('check function', function()
    it('runs complete health check without error', function()
      local health_calls = {}

      vim.health.start = function(msg)
        table.insert(health_calls, { 'start', msg })
      end
      vim.health.ok = function(msg)
        table.insert(health_calls, { 'ok', msg })
      end
      vim.health.warn = function(msg)
        table.insert(health_calls, { 'warn', msg })
      end
      vim.health.error = function(msg)
        table.insert(health_calls, { 'error', msg })
      end
      vim.health.info = function(msg)
        table.insert(health_calls, { 'info', msg })
      end

      assert.has_no_errors(function()
        health.check()
      end)

      assert.is_true(#health_calls > 0)
      assert.equals('start', health_calls[1][1])
      assert.equals('cp.nvim health check', health_calls[1][2])
    end)

    it('reports version information', function()
      local info_messages = {}
      vim.health.start = function() end
      vim.health.ok = function() end
      vim.health.warn = function() end
      vim.health.error = function() end
      vim.health.info = function(msg)
        table.insert(info_messages, msg)
      end

      health.check()

      local version_reported = false
      for _, msg in ipairs(info_messages) do
        if msg:match('^Version:') then
          version_reported = true
          break
        end
      end
      assert.is_true(version_reported)
    end)

    it('checks neovim version compatibility', function()
      local messages = {}
      vim.health.start = function() end
      vim.health.ok = function(msg)
        table.insert(messages, { 'ok', msg })
      end
      vim.health.error = function(msg)
        table.insert(messages, { 'error', msg })
      end
      vim.health.warn = function() end
      vim.health.info = function() end

      health.check()

      local nvim_check_found = false
      for _, msg in ipairs(messages) do
        if msg[2]:match('Neovim') then
          nvim_check_found = true
          if vim.fn.has('nvim-0.10.0') == 1 then
            assert.equals('ok', msg[1])
            assert.is_true(msg[2]:match('detected'))
          else
            assert.equals('error', msg[1])
            assert.is_true(msg[2]:match('requires'))
          end
          break
        end
      end
      assert.is_true(nvim_check_found)
    end)

    it('checks uv executable availability', function()
      local messages = {}
      vim.health.start = function() end
      vim.health.ok = function(msg)
        table.insert(messages, { 'ok', msg })
      end
      vim.health.warn = function(msg)
        table.insert(messages, { 'warn', msg })
      end
      vim.health.error = function() end
      vim.health.info = function() end

      health.check()

      local uv_check_found = false
      for _, msg in ipairs(messages) do
        if msg[2]:match('uv') then
          uv_check_found = true
          if vim.fn.executable('uv') == 1 then
            assert.equals('ok', msg[1])
            assert.is_true(msg[2]:match('found'))
          else
            assert.equals('warn', msg[1])
            assert.is_true(msg[2]:match('not found'))
          end
          break
        end
      end
      assert.is_true(uv_check_found)
    end)

    it('validates scraper files exist', function()
      local messages = {}
      vim.health.start = function() end
      vim.health.ok = function(msg)
        table.insert(messages, { 'ok', msg })
      end
      vim.health.error = function(msg)
        table.insert(messages, { 'error', msg })
      end
      vim.health.warn = function() end
      vim.health.info = function() end

      health.check()

      local scrapers = { 'atcoder.py', 'codeforces.py', 'cses.py' }
      for _, scraper in ipairs(scrapers) do
        local found = false
        for _, msg in ipairs(messages) do
          if msg[2]:match(scraper) then
            found = true
            break
          end
        end
        assert.is_true(found, 'Expected health check for ' .. scraper)
      end
    end)

    it('reports luasnip availability', function()
      local info_messages = {}
      vim.health.start = function() end
      vim.health.ok = function(msg)
        table.insert(info_messages, msg)
      end
      vim.health.warn = function() end
      vim.health.error = function() end
      vim.health.info = function(msg)
        table.insert(info_messages, msg)
      end

      health.check()

      local luasnip_reported = false
      for _, msg in ipairs(info_messages) do
        if msg:match('LuaSnip') then
          luasnip_reported = true
          break
        end
      end
      assert.is_true(luasnip_reported)
    end)

    it('reports current context information', function()
      local info_messages = {}
      vim.health.start = function() end
      vim.health.ok = function() end
      vim.health.warn = function() end
      vim.health.error = function() end
      vim.health.info = function(msg)
        table.insert(info_messages, msg)
      end

      health.check()

      local context_reported = false
      for _, msg in ipairs(info_messages) do
        if msg:match('context') then
          context_reported = true
          break
        end
      end
      assert.is_true(context_reported)
    end)

    it('indicates plugin readiness', function()
      local ok_messages = {}
      vim.health.start = function() end
      vim.health.ok = function(msg)
        table.insert(ok_messages, msg)
      end
      vim.health.warn = function() end
      vim.health.error = function() end
      vim.health.info = function() end

      health.check()

      local ready_reported = false
      for _, msg in ipairs(ok_messages) do
        if msg:match('ready') then
          ready_reported = true
          break
        end
      end
      assert.is_true(ready_reported)
    end)
  end)
end)
