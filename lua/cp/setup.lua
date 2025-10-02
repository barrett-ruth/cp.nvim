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
    logger.log(
      ('unknown platform: %s. supported: %s'):format(platform, table.concat(platforms, ', ')),
      vim.log.levels.ERROR
    )
    return false
  end

  if state.get_platform() == platform then
    logger.log(('platform already set to %s'):format(platform))
  else
    state.set_platform(platform)
    logger.log(('platform set to %s'):format(platform))
  end

  return true
end

local function scrape_contest_problems(problems)
  cache.load()
  local missing_problems = {}

  local platform, contest_id = state.get_platform() or '', state.get_contest_id() or ''

  for _, prob in ipairs(problems) do
    local cached_tests = cache.get_test_cases(platform, contest_id, prob.id)
    if not cached_tests then
      table.insert(missing_problems, prob)
    end
  end

  if vim.tbl_isempty(missing_problems) then
    logger.log(('All problems already cached for %s contest %s.'):format(platform, contest_id))
    return
  end

  for _, prob in ipairs(missing_problems) do
    scraper.scrape_problem_tests(platform, contest_id, prob.id, function(result)
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
        state.get_problem_id(),
        cached_tests,
        result.timeout_ms,
        result.memory_mb
      )
    end)
  end
end

function M.setup_contest(platform, contest_id, language, problem_id)
  if not platform then
    logger.log('No platform configured. Use :CP <platform> <contest> [--{lang=<lang>,debug} first.')
    return
  end

  local config = config_module.get_config()

  if not vim.tbl_contains(config.scrapers, platform) then
    logger.log(('Scraping disabled for %s.'):format(platform), vim.log.levels.WARN)
    return
  end

  state.set_contest_id(contest_id)
  local contest_data = cache.get_contest_data(platform, contest_id)

  if
    not contest_data
    or not contest_data.problems
    or (problem_id and not cache.get_test_cases(platform, contest_id, problem_id))
  then
    logger.log('Fetching contests problems...', vim.log.levels.INFO, true)
    scraper.scrape_contest_metadata(platform, contest_id, function(result)
      local problems = result.problems

      cache.set_contest_data(platform, contest_id, problems)

      logger.log(('Found %d problems for %s contest %s.'):format(#problems, platform, contest_id))

      M.setup_problem(problem_id or problems[1].id, language)

      scrape_contest_problems(problems)
    end)
  else
    M.setup_problem(problem_id, language)
  end
end

---@param problem_id string
---@param language? string
function M.setup_problem(problem_id, language)
  local platform = state.get_platform()
  if not platform then
    logger.log(
      'No platform set. run :CP <platform> <contest> [--{lang=<lang>,debug}]',
      vim.log.levels.ERROR
    )
    return
  end

  state.set_problem_id(problem_id)

  local config = config_module.get_config()

  vim.schedule(function()
    vim.cmd.only({ mods = { silent = true } })

    local source_file = state.get_source_file(language)
    if not source_file then
      return
    end
    vim.cmd.e(source_file)
    local source_buf = vim.api.nvim_get_current_buf()

    if vim.api.nvim_buf_get_lines(source_buf, 0, -1, true)[1] == '' then
      local has_luasnip, luasnip = pcall(require, 'luasnip')
      if has_luasnip then
        local filetype = vim.api.nvim_get_option_value('filetype', { buf = source_buf })
        local language_name = constants.filetype_to_language[filetype]
        local canonical_language = constants.canonical_filetypes[language_name] or language_name
        local prefixed_trigger = ('cp.nvim/%s.%s'):format(platform, canonical_language)

        vim.api.nvim_buf_set_lines(0, 0, -1, false, { prefixed_trigger })
        vim.api.nvim_win_set_cursor(0, { 1, #prefixed_trigger })
        vim.cmd.startinsert({ bang = true })

        vim.schedule(function()
          if luasnip.expandable() then
            luasnip.expand()
          else
            vim.api.nvim_buf_set_lines(0, 0, 1, false, { '' })
            vim.api.nvim_win_set_cursor(0, { 1, 0 })
          end
          vim.cmd.stopinsert()
        end)
      end
    end

    if config.hooks and config.hooks.setup_code then
      config.hooks.setup_code(state)
    end

    cache.set_file_state(
      vim.fn.expand('%:p'),
      platform,
      state.get_contest_id() or '',
      state.get_problem_id(),
      language
    )
  end)
end

function M.navigate_problem(direction, language)
  if direction == 0 then
    return
  end

  direction = direction > 0 and 1 or -1

  local platform = state.get_platform()
  local contest_id = state.get_contest_id()
  local current_problem_id = state.get_problem_id()

  if not platform or not contest_id or not current_problem_id then
    logger.log(
      'No platform configured. Use :CP <platform> <contest> [--{lang=<lang>,debug}] first.',
      vim.log.levels.ERROR
    )
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
  local current_index = nil
  for i, prob in ipairs(problems) do
    if prob.id == current_problem_id then
      current_index = i
      break
    end
  end

  local new_index = current_index + direction
  if new_index < 1 or new_index > #problems then
    return
  end

  M.setup_contest(platform, contest_id, language, problems[new_index].id)
end

return M
