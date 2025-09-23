local M = {}
local cache = require('cp.cache')
local utils = require('cp.utils')

local function run_scraper(platform, subcommand, args, callback)
  if not utils.setup_python_env() then
    callback({ success = false, error = 'Python environment setup failed' })
    return
  end

  local plugin_path = utils.get_plugin_path()
  local cmd = {
    'uv',
    'run',
    '--directory',
    plugin_path,
    '-m',
    'scrapers.' .. platform,
    subcommand,
  }

  for _, arg in ipairs(args or {}) do
    table.insert(cmd, arg)
  end

  vim.system(cmd, {
    cwd = plugin_path,
    text = true,
    timeout = 30000,
  }, function(result)
    if result.code ~= 0 then
      callback({
        success = false,
        error = 'Scraper failed: ' .. (result.stderr or 'Unknown error'),
      })
      return
    end

    local ok, data = pcall(vim.json.decode, result.stdout)
    if not ok then
      callback({
        success = false,
        error = 'Failed to parse scraper output: ' .. tostring(data),
      })
      return
    end

    callback(data)
  end)
end

function M.scrape_contest_metadata(platform, contest_id, callback)
  cache.load()

  local cached = cache.get_contest_data(platform, contest_id)
  if cached then
    callback({ success = true, problems = cached.problems })
    return
  end

  run_scraper(platform, 'metadata', { contest_id }, function(result)
    if result.success and result.problems then
      cache.set_contest_data(platform, contest_id, result.problems)
    end
    callback(result)
  end)
end

function M.scrape_contest_list(platform, callback)
  cache.load()

  local cached = cache.get_contest_list(platform)
  if cached then
    callback({ success = true, contests = cached })
    return
  end

  run_scraper(platform, 'contests', {}, function(result)
    if result.success and result.contests then
      cache.set_contest_list(platform, result.contests)
    end
    callback(result)
  end)
end

function M.scrape_problem_tests(platform, contest_id, problem_id, callback)
  run_scraper(platform, 'tests', { contest_id, problem_id }, function(result)
    if result.success and result.tests then
      vim.schedule(function()
        local mkdir_ok = pcall(vim.fn.mkdir, 'io', 'p')
        if mkdir_ok then
          local config = require('cp.config')
          local base_name = config.default_filename(contest_id, problem_id)
          local logger = require('cp.log')

          logger.log(
            ('writing %d test files for %s (base: %s)'):format(#result.tests, problem_id, base_name)
          )

          for i, test_case in ipairs(result.tests) do
            local input_file = 'io/' .. base_name .. '.' .. i .. '.cpin'
            local expected_file = 'io/' .. base_name .. '.' .. i .. '.cpout'

            local input_content = test_case.input:gsub('\r', '')
            local expected_content = test_case.expected:gsub('\r', '')

            local input_ok =
              pcall(vim.fn.writefile, vim.split(input_content, '\n', true), input_file)
            local expected_ok =
              pcall(vim.fn.writefile, vim.split(expected_content, '\n', true), expected_file)

            if input_ok and expected_ok then
              logger.log(('wrote test files: %s, %s'):format(input_file, expected_file))
            else
              logger.log(
                ('failed to write test files for %s.%d'):format(base_name, i),
                vim.log.levels.WARN
              )
            end
          end
        else
          local logger = require('cp.log')
          logger.log('failed to create io/ directory', vim.log.levels.ERROR)
        end
      end)

      local cached_tests = {}
      for i, test_case in ipairs(result.tests) do
        table.insert(cached_tests, {
          index = i,
          input = test_case.input,
          expected = test_case.expected,
        })
      end

      cache.set_test_cases(
        platform,
        contest_id,
        problem_id,
        cached_tests,
        result.timeout_ms,
        result.memory_mb
      )
    end

    callback(result)
  end)
end

return M
