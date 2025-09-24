local M = {}

local cache = require('cp.cache')
local config = require('cp.config').get_config()
local logger = require('cp.log')
local utils = require('cp.utils')

---@class cp.PlatformItem
---@field id string Platform identifier (e.g. "codeforces", "atcoder", "cses")
---@field display_name string Human-readable platform name (e.g. "Codeforces", "AtCoder", "CSES")

---@class cp.ContestItem
---@field id string Contest identifier (e.g. "1951", "abc324", "sorting")
---@field name string Full contest name (e.g. "Educational Codeforces Round 168")
---@field display_name string Formatted display name for picker

---@class cp.ProblemItem
---@field id string Problem identifier (e.g. "a", "b", "c")
---@field name string Problem name (e.g. "Two Permutations", "Painting Walls")
---@field display_name string Formatted display name for picker

---@return cp.PlatformItem[]
local function get_platforms()
  local constants = require('cp.constants')
  local result = {}

  for _, platform in ipairs(constants.PLATFORMS) do
    if config.contests[platform] then
      table.insert(result, {
        id = platform,
        display_name = constants.PLATFORM_DISPLAY_NAMES[platform] or platform,
      })
    end
  end

  return result
end

---Get list of contests for a specific platform
---@param platform string Platform identifier (e.g. "codeforces", "atcoder")
---@return cp.ContestItem[]
local function get_contests_for_platform(platform)
  logger.log('loading contests...', vim.log.levels.INFO, true)

  cache.load()
  local cached_contests = cache.get_contest_list(platform)
  if cached_contests then
    return cached_contests
  end

  if not utils.setup_python_env() then
    return {}
  end

  local plugin_path = utils.get_plugin_path()
  local cmd = {
    'uv',
    'run',
    '--directory',
    plugin_path,
    '-m',
    'scrapers.' .. platform,
    'contests',
  }

  local result = vim
    .system(cmd, {
      cwd = plugin_path,
      text = true,
      timeout = 30000,
    })
    :wait()

  logger.log(('exit code: %d, stdout length: %d'):format(result.code, #(result.stdout or '')))
  if result.stderr and #result.stderr > 0 then
    logger.log(('stderr: %s'):format(result.stderr:sub(1, 200)))
  end

  if result.code ~= 0 then
    logger.log(
      ('Failed to load contests: %s'):format(result.stderr or 'unknown error'),
      vim.log.levels.ERROR
    )
    return {}
  end

  logger.log(('stdout preview: %s'):format(result.stdout:sub(1, 100)))

  local ok, data = pcall(vim.json.decode, result.stdout)
  if not ok then
    logger.log(('JSON parse error: %s'):format(tostring(data)), vim.log.levels.ERROR)
    return {}
  end
  if not data.success then
    logger.log(
      ('Scraper returned success=false: %s'):format(data.error or 'no error message'),
      vim.log.levels.ERROR
    )
    return {}
  end

  local contests = {}
  for _, contest in ipairs(data.contests or {}) do
    table.insert(contests, {
      id = contest.id,
      name = contest.name,
      display_name = contest.display_name,
    })
  end

  cache.set_contest_list(platform, contests)
  logger.log(('loaded %d contests'):format(#contests))
  return contests
end

---@param platform string Platform identifier
---@param contest_id string Contest identifier
---@return cp.ProblemItem[]
local function get_problems_for_contest(platform, contest_id)
  local constants = require('cp.constants')
  local platform_display_name = constants.PLATFORM_DISPLAY_NAMES[platform] or platform
  local problems = {}

  cache.load()
  local contest_data = cache.get_contest_data(platform, contest_id)
  if contest_data and contest_data.problems then
    for _, problem in ipairs(contest_data.problems) do
      table.insert(problems, {
        id = problem.id,
        name = problem.name,
        display_name = problem.name,
      })
    end
    return problems
  end

  logger.log('loading contest problems...', vim.log.levels.INFO, true)

  if not utils.setup_python_env() then
    return problems
  end

  local plugin_path = utils.get_plugin_path()
  local cmd = {
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
    .system(cmd, {
      cwd = plugin_path,
      text = true,
      timeout = 30000,
    })
    :wait()

  if result.code ~= 0 then
    logger.log(
      ('Failed to scrape contest: %s'):format(result.stderr or 'unknown error'),
      vim.log.levels.ERROR
    )
    return problems
  end

  local ok, data = pcall(vim.json.decode, result.stdout)
  if not ok then
    logger.log('Failed to parse contest data', vim.log.levels.ERROR)
    return problems
  end
  if not data.success then
    logger.log(data.error or 'Contest scraping failed', vim.log.levels.ERROR)
    return problems
  end

  if not data.problems or #data.problems == 0 then
    logger.log('Contest has no problems available', vim.log.levels.WARN)
    return problems
  end

  cache.set_contest_data(platform, contest_id, data.problems)

  for _, problem in ipairs(data.problems) do
    table.insert(problems, {
      id = problem.id,
      name = problem.name,
      display_name = problem.name,
    })
  end

  return problems
end

---@param platform string Platform identifier
---@param contest_id string Contest identifier
---@param problem_id string Problem identifier
local function setup_problem(platform, contest_id, problem_id)
  vim.schedule(function()
    local cp = require('cp')
    cp.handle_command({ fargs = { platform, contest_id, problem_id } })
  end)
end

M.get_platforms = get_platforms
M.get_contests_for_platform = get_contests_for_platform
M.get_problems_for_contest = get_problems_for_contest
M.setup_problem = setup_problem

return M
