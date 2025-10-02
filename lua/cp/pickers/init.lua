local M = {}

local cache = require('cp.cache')
local config = require('cp.config').get_config()
local constants = require('cp.constants')
local logger = require('cp.log')
local scraper = require('cp.scraper')

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
function M.get_platforms()
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
---@param refresh? boolean Whether to skip caching and append new contests
---@return cp.ContestItem[]
function M.get_platform_contests(platform, refresh)
  logger.log(
    ('Loading %s contests...'):format(constants.PLATFORM_DISPLAY_NAMES[platform]),
    vim.log.levels.INFO,
    true
  )

  cache.load()

  local picker_contests = cache.get_contest_summaries(platform)

  if refresh or vim.tbl_isempty(picker_contests) then
    logger.log(('Cache miss on %s contests'):format(platform))
    local contests = scraper.scrape_contest_list(platform)

    cache.set_contest_summaries(platform, contests)
  end

  logger.log(
    ('Loaded %s %s contests.'):format(#picker_contests, constants.PLATFORM_DISPLAY_NAMES[platform]),
    vim.log.levels.INFO,
    true
  )

  picker_contests = cache.get_contest_summaries(platform)

  return picker_contests
end

return M
