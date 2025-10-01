local M = {}
local utils = require('cp.utils')

local logger = require('cp.log')

local function syshandle(result)
  if result.code ~= 0 then
    local msg = 'Scraper failed: ' .. (result.error or result.stderr or 'Unknown error')
    logger.log(msg, vim.log.levels.ERROR)
    return {
      success = false,
      error = msg,
    }
  end

  local ok, data = pcall(vim.json.decode, result.stdout)
  if not ok then
    local msg = 'Failed to parse scraper output: ' .. tostring(data)
    logger.log(msg, vim.log.levels.ERROR)
    return {
      success = false,
      error = msg,
    }
  end

  return {
    success = true,
    data = data,
  }
end

local function run_scraper(platform, subcommand, args, opts)
  if not utils.setup_python_env() then
    local msg = 'Python environment setup failed'
    logger.log(msg, vim.log.levels.ERROR)
    return {
      success = false,
      message = msg,
    }
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
  vim.list_extend(cmd, args)

  local sysopts = {
    text = true,
    timeout = 30000,
  }

  if opts.sync then
    local result = vim.system(cmd, sysopts):wait()
    return syshandle(result)
  else
    vim.system(cmd, sysopts, function(result)
      return opts.on_exit(syshandle(result))
    end)
  end
end

function M.scrape_contest_metadata(platform, contest_id, callback)
  run_scraper(platform, 'metadata', { contest_id }, {
    on_exit = function(result)
      if result.success and result.data.problems then
        callback(result.data.problems)
      end
    end,
  })
end

function M.scrape_contest_list(platform)
  local result = run_scraper(platform, 'contests', {}, { sync = true })
  if not result.success or not result.data.contests then
    logger.log(('Could not scrape contests list for platform %s: %s'):format(platform, result.msg))
    return {}
  end

  return result.data.contests
end

function M.scrape_problem_tests(platform, contest_id, problem_id, callback)
  run_scraper(platform, 'tests', { contest_id, problem_id }, {
    on_exit = function(result)
      if result.success and result.data.tests then
        vim.schedule(function()
          local mkdir_ok = pcall(vim.fn.mkdir, 'io', 'p')
          if mkdir_ok then
            local config = require('cp.config')
            local base_name = config.default_filename(contest_id, problem_id)

            for i, test_case in ipairs(result.tests) do
              local input_file = 'io/' .. base_name .. '.' .. i .. '.cpin'
              local expected_file = 'io/' .. base_name .. '.' .. i .. '.cpout'

              local input_content = test_case.input:gsub('\r', '')
              local expected_content = test_case.expected:gsub('\r', '')

              pcall(
                vim.fn.writefile,
                vim.split(input_content, '\n', { trimempty = true }),
                input_file
              )
              pcall(
                vim.fn.writefile,
                vim.split(expected_content, '\n', { trimempty = true }),
                expected_file
              )
            end
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
    end,
  })
end

return M
