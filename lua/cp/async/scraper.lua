local M = {}
local cache = require('cp.cache')
local jobs = require('cp.async.jobs')
local utils = require('cp.utils')

local function check_internet_connectivity()
  local result = vim.system({ 'ping', '-c', '5', '-W', '3', '8.8.8.8' }, { text = true }):wait()
  return result.code == 0
end

function M.scrape_contest_metadata_async(platform, contest_id, callback)
  vim.validate({
    platform = { platform, 'string' },
    contest_id = { contest_id, 'string' },
    callback = { callback, 'function' },
  })

  cache.load()

  local cached_data = cache.get_contest_data(platform, contest_id)
  if cached_data then
    callback({
      success = true,
      problems = cached_data.problems,
    })
    return
  end

  if not check_internet_connectivity() then
    callback({
      success = false,
      error = 'No internet connection available',
    })
    return
  end

  if not utils.setup_python_env() then
    callback({
      success = false,
      error = 'Python environment setup failed',
    })
    return
  end

  local plugin_path = utils.get_plugin_path()

  local args = {
    'uv',
    'run',
    '--directory',
    plugin_path,
    '-m',
    'scrapers.' .. platform,
    'metadata',
    contest_id,
  }

  local job_id = 'contest_metadata_' .. platform .. '_' .. contest_id

  jobs.start_job(job_id, args, {
    cwd = plugin_path,
    text = true,
    timeout = 30000,
  }, function(result)
    if result.code ~= 0 then
      callback({
        success = false,
        error = 'Failed to run metadata scraper: ' .. (result.stderr or 'Unknown error'),
      })
      return
    end

    local ok, data = pcall(vim.json.decode, result.stdout)
    if not ok then
      callback({
        success = false,
        error = 'Failed to parse metadata scraper output: ' .. tostring(data),
      })
      return
    end

    if not data.success then
      callback(data)
      return
    end

    local problems_list = data.problems or {}
    cache.set_contest_data(platform, contest_id, problems_list)

    callback({
      success = true,
      problems = problems_list,
    })
  end)
end

function M.scrape_problem_async(platform, contest_id, problem_id, callback)
  vim.validate({
    platform = { platform, 'string' },
    contest_id = { contest_id, 'string' },
    problem_id = { problem_id, 'string' },
    callback = { callback, 'function' },
  })

  if not check_internet_connectivity() then
    callback({
      success = false,
      problem_id = problem_id,
      error = 'No internet connection available',
    })
    return
  end

  if not utils.setup_python_env() then
    callback({
      success = false,
      problem_id = problem_id,
      error = 'Python environment setup failed',
    })
    return
  end

  local plugin_path = utils.get_plugin_path()

  local args = {
    'uv',
    'run',
    '--directory',
    plugin_path,
    '-m',
    'scrapers.' .. platform,
    'tests',
    contest_id,
    problem_id,
  }

  local job_id = 'problem_tests_' .. platform .. '_' .. contest_id .. '_' .. problem_id

  jobs.start_job(job_id, args, {
    cwd = plugin_path,
    text = true,
    timeout = 30000,
  }, function(result)
    if result.code ~= 0 then
      callback({
        success = false,
        problem_id = problem_id,
        error = 'Failed to run tests scraper: ' .. (result.stderr or 'Unknown error'),
      })
      return
    end

    local ok, data = pcall(vim.json.decode, result.stdout)
    if not ok then
      callback({
        success = false,
        problem_id = problem_id,
        error = 'Failed to parse tests scraper output: ' .. tostring(data),
      })
      return
    end

    if not data.success then
      callback(data)
      return
    end

    if data.tests and #data.tests > 0 then
      vim.fn.mkdir('io', 'p')

      local cached_test_cases = {}
      for i, test_case in ipairs(data.tests) do
        table.insert(cached_test_cases, {
          index = i,
          input = test_case.input,
          expected = test_case.expected,
        })
      end

      cache.set_test_cases(
        platform,
        contest_id,
        problem_id,
        cached_test_cases,
        data.timeout_ms,
        data.memory_mb
      )
    end

    callback({
      success = true,
      problem_id = problem_id,
      test_count = data.tests and #data.tests or 0,
      test_cases = data.tests,
      timeout_ms = data.timeout_ms,
      memory_mb = data.memory_mb,
      url = data.url,
    })
  end)
end

return M
