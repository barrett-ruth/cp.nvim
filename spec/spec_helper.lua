local M = {}

M.logged_messages = {}

local mock_logger = {
  log = function(msg, level)
    table.insert(M.logged_messages, { msg = msg, level = level })
  end,
  set_config = function() end,
}

local function setup_vim_mocks()
  if not vim.fn then
    vim.fn = {}
  end
  vim.fn.expand = vim.fn.expand or function()
    return '/tmp/test.cpp'
  end
  vim.fn.mkdir = vim.fn.mkdir or function() end
  vim.fn.fnamemodify = vim.fn.fnamemodify or function(path)
    return path
  end
  vim.fn.tempname = vim.fn.tempname or function()
    return '/tmp/session'
  end
  if not vim.api then
    vim.api = {}
  end
  vim.api.nvim_get_current_buf = vim.api.nvim_get_current_buf or function()
    return 1
  end
  vim.api.nvim_buf_get_lines = vim.api.nvim_buf_get_lines or function()
    return { '' }
  end
  if not vim.cmd then
    vim.cmd = {}
  end
  vim.cmd = {
    only = function() end,
    e = function() end,
    split = function() end,
    vsplit = function() end,
    startinsert = function() end,
    stopinsert = function() end,
  }
  if not vim.system then
    vim.system = function(_)
      return {
        wait = function()
          return { code = 0 }
        end,
      }
    end
  end
end

function M.setup()
  M.logged_messages = {}
  package.loaded['cp.log'] = mock_logger
end

function M.setup_full()
  M.setup()
  setup_vim_mocks()

  local cache = require('cp.cache')
  cache.load = function() end
  cache.set_test_cases = function() end
  cache.set_file_state = function() end
  cache.get_file_state = function()
    return nil
  end
  cache.get_contest_data = function()
    return nil
  end
  cache.get_test_cases = function()
    return {}
  end
end

function M.mock_scraper_success()
  package.loaded['cp.scrape'] = {
    scrape_problem = function()
      local state = require('cp.state')
      return {
        success = true,
        problem_id = state.get_problem_id(),
        test_cases = {
          { input = '1 2', expected = '3' },
          { input = '3 4', expected = '7' },
        },
        test_count = 2,
      }
    end,
    scrape_contest_metadata = function(_, _)
      return {
        success = true,
        problems = {
          { id = 'a' },
          { id = 'b' },
          { id = 'c' },
        },
      }
    end,
    scrape_problems_parallel = function()
      return {}
    end,
  }
end

function M.mock_async_scraper_success()
  package.loaded['cp.async.scraper'] = {
    scrape_contest_metadata_async = function(_, _, callback)
      vim.schedule(function()
        callback({
          success = true,
          problems = {
            { id = 'a' },
            { id = 'b' },
            { id = 'c' },
          },
        })
      end)
    end,
    scrape_problem_async = function(_, _, problem_id, callback)
      vim.schedule(function()
        callback({
          success = true,
          problem_id = problem_id,
          test_cases = {
            { input = '1 2', expected = '3' },
            { input = '3 4', expected = '7' },
          },
          test_count = 2,
          timeout_ms = 2000,
          memory_mb = 256.0,
          url = 'https://example.com',
        })
      end)
    end,
  }
end

function M.mock_async_scraper_failure()
  package.loaded['cp.async.scraper'] = {
    scrape_contest_metadata_async = function(_, _, callback)
      vim.schedule(function()
        callback({
          success = false,
          error = 'mock network error',
        })
      end)
    end,
    scrape_problem_async = function(_, _, problem_id, callback)
      vim.schedule(function()
        callback({
          success = false,
          problem_id = problem_id,
          error = 'mock scraping failed',
        })
      end)
    end,
  }
end

function M.has_error_logged()
  for _, log_entry in ipairs(M.logged_messages) do
    if log_entry.level == vim.log.levels.ERROR then
      return true
    end
  end
  return false
end

function M.find_logged_message(pattern)
  for _, log_entry in ipairs(M.logged_messages) do
    if log_entry.msg and log_entry.msg:match(pattern) then
      return log_entry
    end
  end
  return nil
end

function M.fresh_require(module_name, additional_clears)
  additional_clears = additional_clears or {}

  for _, clear_module in ipairs(additional_clears) do
    package.loaded[clear_module] = nil
  end
  package.loaded[module_name] = nil

  return require(module_name)
end

function M.teardown()
  package.loaded['cp.log'] = nil
  package.loaded['cp.scrape'] = nil
  package.loaded['cp.async.scraper'] = nil
  package.loaded['cp.async.jobs'] = nil
  package.loaded['cp.async.setup'] = nil
  package.loaded['cp.async'] = nil
  M.logged_messages = {}
end

return M
