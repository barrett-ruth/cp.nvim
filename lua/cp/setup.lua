local M = {}

local cache = require('cp.cache')
local config_module = require('cp.config')
local logger = require('cp.log')
local scraper = require('cp.scraper')
local state = require('cp.state')

local constants = require('cp.constants')
local platforms = constants.PLATFORMS

function M.set_platform(platform)
  if not vim.tbl_contains(platforms, platform) then
    logger.log(("Unknown platform '%s'"):format(platform), vim.log.levels.ERROR)
    return false
  end
  state.set_platform(platform)
  return true
end

---@class TestCaseLite
---@field input string
---@field expected string

---@class ScrapeEvent
---@field problem_id string
---@field tests TestCaseLite[]|nil
---@field timeout_ms integer|nil
---@field memory_mb integer|nil
---@field interactive boolean|nil
---@field error string|nil
---@field done boolean|nil
---@field succeeded integer|nil
---@field failed integer|nil

---@param platform string
---@param contest_id string
---@param problem_id string|nil
---@param language? string|nil
function M.setup_contest(platform, contest_id, problem_id, language)
  state.set_contest_id(contest_id)
  cache.load()

  local function proceed(contest_data)
    local problems = contest_data.problems
    local pid = problems[(problem_id and contest_data.index_map[problem_id] or 1)].id
    M.setup_problem(pid, language)

    local cached_len = #vim.tbl_filter(function(p)
      return not vim.tbl_isempty(cache.get_test_cases(platform, contest_id, p.id))
    end, problems)

    if cached_len ~= #problems then
      logger.log(('Fetching test cases...'):format(cached_len, #problems))
      scraper.scrape_all_tests(platform, contest_id, function(ev)
        local cached_tests = {}
        if not ev.interactive and vim.tbl_isempty(ev.tests) then
          logger.log(
            ("No tests found for problem '%s'."):format(ev.problem_id),
            vim.log.levels.WARN
          )
        end
        for i, t in ipairs(ev.tests) do
          cached_tests[i] = { index = i, input = t.input, expected = t.expected }
        end
        cache.set_test_cases(
          platform,
          contest_id,
          ev.problem_id,
          cached_tests,
          ev.timeout_ms or 0,
          ev.memory_mb or 0,
          ev.interactive
        )
        logger.log('Test cases loaded.')
      end)
    end
  end

  local contest_data = cache.get_contest_data(platform, contest_id)
  if not contest_data or not contest_data.problems then
    logger.log('Fetching contests problems...', vim.log.levels.INFO, true)
    scraper.scrape_contest_metadata(platform, contest_id, function(result)
      local problems = result.problems or {}
      cache.set_contest_data(platform, contest_id, problems)
      logger.log(('Found %d problems for %s contest %s.'):format(#problems, platform, contest_id))
      proceed(cache.get_contest_data(platform, contest_id))
    end)
    return
  end

  proceed(contest_data)
end

---@param problem_id string
---@param language? string
function M.setup_problem(problem_id, language)
  local platform = state.get_platform()
  if not platform then
    logger.log('No platform set.', vim.log.levels.ERROR)
    return
  end

  state.set_problem_id(problem_id)

  local config = config_module.get_config()

  vim.schedule(function()
    vim.cmd.only({ mods = { silent = true } })

    local lang = language or config.platforms[platform].default_language
    local source_file = state.get_source_file(lang)
    vim.cmd.e(source_file)

    if config.hooks and config.hooks.setup_code then
      config.hooks.setup_code(state)
    end

    cache.set_file_state(
      vim.fn.expand('%:p'),
      platform,
      state.get_contest_id() or '',
      state.get_problem_id() or '',
      lang
    )
  end)
end

function M.navigate_problem(direction)
  if direction == 0 then
    return
  end
  direction = direction > 0 and 1 or -1

  local platform = state.get_platform()
  local contest_id = state.get_contest_id()
  local current_problem_id = state.get_problem_id()

  if not platform or not contest_id or not current_problem_id then
    logger.log('No platform configured.', vim.log.levels.ERROR)
    return
  end

  cache.load()
  local contest_data = cache.get_contest_data(platform, contest_id)
  if not contest_data or not contest_data.problems then
    logger.log(
      ('No data available for %s contest %s.'):format(
        constants.PLATFORM_DISPLAY_NAMES[platform],
        contest_id
      ),
      vim.log.levels.ERROR
    )
    return
  end

  local problems = contest_data.problems
  local index = contest_data.index_map[current_problem_id]
  local new_index = index + direction
  if new_index < 1 or new_index > #problems then
    return
  end

  require('cp.ui.panel').disable()
  M.setup_contest(platform, contest_id, problems[new_index].id)
end

return M
