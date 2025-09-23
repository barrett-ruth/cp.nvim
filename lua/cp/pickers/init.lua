local M = {}

local cache = require('cp.cache')
local logger = require('cp.log')
local scraper = require('cp.scraper')
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
  cache.load()
  local cached_contests = cache.get_contest_list(platform)
  if cached_contests then
    return cached_contests
  end

  local constants = require('cp.constants')
  local platform_display_name = constants.PLATFORM_DISPLAY_NAMES[platform] or platform
  logger.log(('Loading %s contests...'):format(platform_display_name), vim.log.levels.INFO, true)

  scraper.scrape_contest_list(platform, function(result)
    if result.success then
      logger.log(
        ('Loaded %d contests for %s'):format(#(result.contests or {}), platform_display_name),
        vim.log.levels.INFO,
        true
      )
    else
      logger.log(
        ('Failed to load contests for %s: %s'):format(platform, result.error or 'unknown error'),
        vim.log.levels.ERROR
      )
    end
  end)

  return {}
end

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

  local constants = require('cp.constants')
  local platform_display_name = constants.PLATFORM_DISPLAY_NAMES[platform] or platform
  logger.log(
    ('Scraping %s %s for problems, this may take a few seconds...'):format(
      platform_display_name,
      contest_id
    ),
    vim.log.levels.INFO,
    true
  )

  local cached_data = cache.get_contest_data(platform, contest_id)
  if not cached_data or not cached_data.problems then
    logger.log(
      'No cached contest data found. Run :CP first to scrape contest metadata.',
      vim.log.levels.WARN
    )
    return problems
  end

  for _, problem in ipairs(cached_data.problems) do
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
