local M = {}

local cache = require('cp.cache')
local logger = require('cp.log')
local scrape = require('cp.scrape')
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

---Get list of available competitive programming platforms
---@return cp.PlatformItem[]
local function get_platforms()
  local constants = require('cp.constants')
  return vim.tbl_map(function(platform)
    return {
      id = platform,
      display_name = constants.PLATFORM_DISPLAY_NAMES[platform] or platform,
    }
  end, constants.PLATFORMS)
end

---Get list of contests for a specific platform
---@param platform string Platform identifier (e.g. "codeforces", "atcoder")
---@return cp.ContestItem[]
local function get_contests_for_platform(platform)
  local contests = {}

  cache.load()
  local cached_contests = cache.get_contest_list(platform)
  if cached_contests then
    return cached_contests
  end

  if not utils.setup_python_env() then
    return contests
  end

  local constants = require('cp.constants')
  local platform_display_name = constants.PLATFORM_DISPLAY_NAMES[platform] or platform
  logger.log(
    ('Scraping %s for contests, this may take a few seconds...'):format(platform_display_name),
    vim.log.levels.INFO
  )

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

  if result.code ~= 0 then
    logger.log(
      ('Failed to get contests for %s: %s'):format(platform, result.stderr or 'unknown error'),
      vim.log.levels.ERROR
    )
    return contests
  end

  local ok, data = pcall(vim.json.decode, result.stdout)
  if not ok or not data.success then
    logger.log(('Failed to parse contest data for %s'):format(platform), vim.log.levels.ERROR)
    return contests
  end

  for _, contest in ipairs(data.contests or {}) do
    table.insert(contests, {
      id = contest.id,
      name = contest.name,
      display_name = contest.display_name,
    })
  end

  cache.set_contest_list(platform, contests)
  return contests
end

---Get list of problems for a specific contest
---@param platform string Platform identifier
---@param contest_id string Contest identifier
---@return cp.ProblemItem[]
local function get_problems_for_contest(platform, contest_id)
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

  local metadata_result = scrape.scrape_contest_metadata(platform, contest_id)
  if not metadata_result.success then
    logger.log(
      ('Failed to get problems for %s %s: %s'):format(
        platform,
        contest_id,
        metadata_result.error or 'unknown error'
      ),
      vim.log.levels.ERROR
    )
    return problems
  end

  for _, problem in ipairs(metadata_result.problems or {}) do
    table.insert(problems, {
      id = problem.id,
      name = problem.name,
      display_name = problem.name,
    })
  end

  return problems
end

---Set up a specific problem by calling the main CP handler
---@param platform string Platform identifier
---@param contest_id string Contest identifier
---@param problem_id string Problem identifier
local function setup_problem(platform, contest_id, problem_id)
  local cp = require('cp')
  cp.handle_command({ fargs = { platform, contest_id, problem_id } })
end

M.get_platforms = get_platforms
M.get_contests_for_platform = get_contests_for_platform
M.get_problems_for_contest = get_problems_for_contest
M.setup_problem = setup_problem

return M
