---@class ScraperTestCase
---@field input string
---@field expected string

---@class ScraperResult
---@field success boolean
---@field problem_id string
---@field url? string
---@field tests? ScraperTestCase[]
---@field timeout_ms? number
---@field memory_mb? number
---@field error? string

local M = {}
local cache = require('cp.cache')
local logger = require('cp.log')
local problem = require('cp.problem')

local function get_plugin_path()
  local plugin_path = debug.getinfo(1, 'S').source:sub(2)
  return vim.fn.fnamemodify(plugin_path, ':h:h:h')
end

local function ensure_io_directory()
  vim.fn.mkdir('io', 'p')
end

local function check_internet_connectivity()
  local result = vim.system({ 'ping', '-c', '1', '-W', '3', '8.8.8.8' }, { text = true }):wait()
  return result.code == 0
end

local function setup_python_env()
  local plugin_path = get_plugin_path()
  local venv_dir = plugin_path .. '/.venv'

  if vim.fn.executable('uv') == 0 then
    logger.log(
      'uv is not installed. Install it to enable problem scraping: https://docs.astral.sh/uv/',
      vim.log.levels.WARN
    )
    return false
  end

  if vim.fn.isdirectory(venv_dir) == 0 then
    logger.log('setting up Python environment for scrapers...')
    local result = vim.system({ 'uv', 'sync' }, { cwd = plugin_path, text = true }):wait()
    if result.code ~= 0 then
      logger.log('failed to setup Python environment: ' .. result.stderr, vim.log.levels.ERROR)
      return false
    end
    logger.log('python environment setup complete')
  end

  return true
end

---@param platform string
---@param contest_id string
---@return {success: boolean, problems?: table[], error?: string}
function M.scrape_contest_metadata(platform, contest_id)
  vim.validate({
    platform = { platform, 'string' },
    contest_id = { contest_id, 'string' },
  })

  cache.load()

  local cached_data = cache.get_contest_data(platform, contest_id)
  if cached_data then
    return {
      success = true,
      problems = cached_data.problems,
    }
  end

  if not check_internet_connectivity() then
    return {
      success = false,
      error = 'No internet connection available',
    }
  end

  if not setup_python_env() then
    return {
      success = false,
      error = 'Python environment setup failed',
    }
  end

  local plugin_path = get_plugin_path()

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

  local result = vim
    .system(args, {
      cwd = plugin_path,
      text = true,
      timeout = 30000,
    })
    :wait()

  if result.code ~= 0 then
    return {
      success = false,
      error = 'Failed to run metadata scraper: ' .. (result.stderr or 'Unknown error'),
    }
  end

  local ok, data = pcall(vim.json.decode, result.stdout)
  if not ok then
    return {
      success = false,
      error = 'Failed to parse metadata scraper output: ' .. tostring(data),
    }
  end

  if not data.success then
    return data
  end

  local problems_list = data.problems or {}

  cache.set_contest_data(platform, contest_id, problems_list)
  return {
    success = true,
    problems = problems_list,
  }
end

---@param ctx ProblemContext
---@return {success: boolean, problem_id: string, test_count?: number, test_cases?: ScraperTestCase[], timeout_ms?: number, memory_mb?: number, url?: string, error?: string}
function M.scrape_problem(ctx)
  vim.validate({
    ctx = { ctx, 'table' },
  })

  ensure_io_directory()

  if vim.fn.filereadable(ctx.input_file) == 1 and vim.fn.filereadable(ctx.expected_file) == 1 then
    local base_name = vim.fn.fnamemodify(ctx.input_file, ':r')
    local test_cases = {}
    local i = 1

    while true do
      local input_file = base_name .. '.' .. i .. '.cpin'
      local expected_file = base_name .. '.' .. i .. '.cpout'

      if vim.fn.filereadable(input_file) == 1 and vim.fn.filereadable(expected_file) == 1 then
        local input_content = table.concat(vim.fn.readfile(input_file), '\n')
        local expected_content = table.concat(vim.fn.readfile(expected_file), '\n')

        table.insert(test_cases, {
          index = i,
          input = input_content,
          output = expected_content,
        })
        i = i + 1
      else
        break
      end
    end

    return {
      success = true,
      problem_id = ctx.problem_name,
      test_count = #test_cases,
      test_cases = test_cases,
    }
  end

  if not check_internet_connectivity() then
    return {
      success = false,
      problem_id = ctx.problem_name,
      error = 'No internet connection available',
    }
  end

  if not setup_python_env() then
    return {
      success = false,
      problem_id = ctx.problem_name,
      error = 'Python environment setup failed',
    }
  end

  local plugin_path = get_plugin_path()

  local args
  if ctx.contest == 'cses' then
    args = {
      'uv',
      'run',
      '--directory',
      plugin_path,
      '-m',
      'scrapers.' .. ctx.contest,
      'tests',
      ctx.problem_id,
    }
  else
    args = {
      'uv',
      'run',
      '--directory',
      plugin_path,
      '-m',
      'scrapers.' .. ctx.contest,
      'tests',
      ctx.contest_id,
      ctx.problem_id,
    }
  end

  local result = vim
    .system(args, {
      cwd = plugin_path,
      text = true,
      timeout = 30000,
    })
    :wait()

  if result.code ~= 0 then
    return {
      success = false,
      problem_id = ctx.problem_name,
      error = 'Failed to run tests scraper: ' .. (result.stderr or 'Unknown error'),
    }
  end

  local ok, data = pcall(vim.json.decode, result.stdout)
  if not ok then
    return {
      success = false,
      problem_id = ctx.problem_name,
      error = 'Failed to parse tests scraper output: ' .. tostring(data),
    }
  end

  if not data.success then
    return data
  end

  if data.tests and #data.tests > 0 then
    local base_name = vim.fn.fnamemodify(ctx.input_file, ':r')

    for i, test_case in ipairs(data.tests) do
      local input_file = base_name .. '.' .. i .. '.cpin'
      local expected_file = base_name .. '.' .. i .. '.cpout'

      local input_content = test_case.input:gsub('\r', '')
      local expected_content = test_case.expected:gsub('\r', '')

      vim.fn.writefile(vim.split(input_content, '\n', true), input_file)
      vim.fn.writefile(vim.split(expected_content, '\n', true), expected_file)
    end

    local cached_test_cases = {}
    for i, test_case in ipairs(data.tests) do
      table.insert(cached_test_cases, {
        index = i,
        input = test_case.input,
        expected = test_case.expected,
      })
    end

    cache.set_test_cases(
      ctx.contest,
      ctx.contest_id,
      ctx.problem_id,
      cached_test_cases,
      data.timeout_ms,
      data.memory_mb
    )
  end

  return {
    success = true,
    problem_id = ctx.problem_name,
    test_count = data.tests and #data.tests or 0,
    test_cases = data.tests,
    timeout_ms = data.timeout_ms,
    memory_mb = data.memory_mb,
    url = data.url,
  }
end

---@param platform string
---@param contest_id string
---@param problems table[]
---@param config table
---@return table[]
function M.scrape_problems_parallel(platform, contest_id, problems, config)
  vim.validate({
    platform = { platform, 'string' },
    contest_id = { contest_id, 'string' },
    problems = { problems, 'table' },
    config = { config, 'table' },
  })

  if not check_internet_connectivity() then
    return {}
  end

  if not setup_python_env() then
    return {}
  end

  local plugin_path = get_plugin_path()
  local jobs = {}

  for _, problem in ipairs(problems) do
    local args
    if platform == 'cses' then
      args = {
        'uv',
        'run',
        '--directory',
        plugin_path,
        '-m',
        'scrapers.' .. platform,
        'tests',
        problem.id,
      }
    else
      args = {
        'uv',
        'run',
        '--directory',
        plugin_path,
        '-m',
        'scrapers.' .. platform,
        'tests',
        contest_id,
        problem.id,
      }
    end

    local job = vim.system(args, {
      cwd = plugin_path,
      text = true,
      timeout = 30000,
    })

    jobs[problem.id] = {
      job = job,
      problem = problem,
    }
  end

  local results = {}
  for problem_id, job_data in pairs(jobs) do
    local result = job_data.job:wait()
    local scrape_result = {
      success = false,
      problem_id = problem_id,
      error = 'Unknown error',
    }

    if result.code == 0 then
      local ok, data = pcall(vim.json.decode, result.stdout)
      if ok and data.success then
        scrape_result = data

        if data.tests and #data.tests > 0 then
          local ctx = problem.create_context(platform, contest_id, problem_id, config)
          local base_name = vim.fn.fnamemodify(ctx.input_file, ':r')

          for i, test_case in ipairs(data.tests) do
            local input_file = base_name .. '.' .. i .. '.cpin'
            local expected_file = base_name .. '.' .. i .. '.cpout'

            local input_content = test_case.input:gsub('\r', '')
            local expected_content = test_case.expected:gsub('\r', '')

            vim.fn.writefile(vim.split(input_content, '\n', true), input_file)
            vim.fn.writefile(vim.split(expected_content, '\n', true), expected_file)
          end

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
      else
        scrape_result.error = ok and data.error or 'Failed to parse scraper output'
      end
    else
      scrape_result.error = 'Scraper execution failed: ' .. (result.stderr or 'Unknown error')
    end

    results[problem_id] = scrape_result
  end

  return results
end

return M
