local M = {}

local cache = require('cp.cache')
local config_module = require('cp.config')
local logger = require('cp.log')
local problem = require('cp.problem')
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

function M.setup_contest(platform, contest_id, problem_id, language)
  if not state.get_platform() then
    logger.log('no platform set', vim.log.levels.ERROR)
    return
  end

  local config = config_module.get_config()

  if not vim.tbl_contains(config.scrapers, platform) then
    logger.log('scraping disabled for ' .. platform, vim.log.levels.WARN)
    return
  end

  logger.log(('setting up contest %s %s'):format(platform, contest_id))

  scraper.scrape_contest_metadata(platform, contest_id, function(result)
    if not result.success then
      logger.log(
        'failed to load contest metadata: ' .. (result.error or 'unknown error'),
        vim.log.levels.ERROR
      )
      return
    end

    local problems = result.problems
    if not problems or #problems == 0 then
      logger.log('no problems found in contest', vim.log.levels.ERROR)
      return
    end

    logger.log(('found %d problems'):format(#problems))

    state.set_contest_id(contest_id)
    local target_problem = problem_id or problems[1].id

    if problem_id then
      local problem_exists = false
      for _, prob in ipairs(problems) do
        if prob.id == problem_id then
          problem_exists = true
          break
        end
      end
      if not problem_exists then
        logger.log(
          ('invalid problem %s for contest %s'):format(problem_id, contest_id),
          vim.log.levels.ERROR
        )
        return
      end
    end

    M.setup_problem(contest_id, target_problem, language)

    M.scrape_remaining_problems(platform, contest_id, problems)
  end)
end

function M.setup_problem(contest_id, problem_id, language)
  if not state.get_platform() then
    logger.log('no platform set. run :CP <platform> <contest> first', vim.log.levels.ERROR)
    return
  end

  local config = config_module.get_config()
  local platform = state.get_platform() or ''

  logger.log(('setting up problem: %s%s'):format(contest_id, problem_id or ''))

  local ctx = problem.create_context(platform, contest_id, problem_id, config, language)

  local cached_tests = cache.get_test_cases(platform, contest_id, problem_id)
  if cached_tests then
    state.set_test_cases(cached_tests)
    logger.log(('using cached test cases (%d)'):format(#cached_tests))
  elseif vim.tbl_contains(config.scrapers, platform) then
    logger.log('loading test cases...')

    scraper.scrape_problem_tests(platform, contest_id, problem_id, function(result)
      vim.schedule(function()
        if result.success then
          logger.log(('loaded %d test cases for %s'):format(#(result.tests or {}), problem_id))
          if state.get_problem_id() == problem_id then
            state.set_test_cases(result.tests)
          end
        else
          logger.log(
            'failed to load tests: ' .. (result.error or 'unknown error'),
            vim.log.levels.ERROR
          )
          if state.get_problem_id() == problem_id then
            state.set_test_cases({})
          end
        end
      end)
    end)
  else
    logger.log(('scraping disabled for %s'):format(platform))
    state.set_test_cases({})
  end

  state.set_contest_id(contest_id)
  state.set_problem_id(problem_id)
  state.set_run_panel_active(false)

  vim.schedule(function()
    local ok, err = pcall(function()
      vim.cmd.only({ mods = { silent = true } })

      vim.cmd.e(ctx.source_file)
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
        else
          vim.api.nvim_input(('i%s<c-space><esc>'):format(platform))
        end
      end

      if config.hooks and config.hooks.setup_code then
        config.hooks.setup_code(ctx)
      end

      cache.set_file_state(vim.fn.expand('%:p'), platform, contest_id, problem_id, language)

      logger.log(('switched to problem %s'):format(ctx.problem_name))
    end)

    if not ok then
      logger.log(('setup error: %s'):format(err), vim.log.levels.ERROR)
    end
  end)
end

function M.scrape_remaining_problems(platform, contest_id, problems)
  cache.load()
  local config = config_module.get_config()
  local missing_problems = {}

  for _, prob in ipairs(problems) do
    local cached_tests = cache.get_test_cases(platform, contest_id, prob.id)
    if not cached_tests then
      table.insert(missing_problems, prob)
    end
  end

  if #missing_problems == 0 then
    logger.log('all problems already cached')
    return
  end

  logger.log(('scraping %d uncached problems in background...'):format(#missing_problems))

  for _, prob in ipairs(missing_problems) do
    logger.log(('starting background scrape for problem %s'):format(prob.id))
    scraper.scrape_problem_tests(platform, contest_id, prob.id, function(result)
      if result.success then
        logger.log(
          ('background: scraped problem %s - %d test cases'):format(prob.id, #(result.tests or {}))
        )
      else
        logger.log(
          ('background: failed to scrape problem %s: %s'):format(
            prob.id,
            result.error or 'unknown error'
          ),
          vim.log.levels.WARN
        )
      end
    end)
  end
end

function M.navigate_problem(direction, language)
  local platform = state.get_platform()
  local contest_id = state.get_contest_id()
  local current_problem_id = state.get_problem_id()

  if not platform or not contest_id or not current_problem_id then
    logger.log('no contest context', vim.log.levels.ERROR)
    return
  end

  cache.load()
  local contest_data = cache.get_contest_data(platform, contest_id)
  if not contest_data or not contest_data.problems then
    logger.log('no contest data available', vim.log.levels.ERROR)
    return
  end

  local problems = contest_data.problems
  local current_index = nil
  for i, problem in ipairs(problems) do
    if problem.id == current_problem_id then
      current_index = i
      break
    end
  end

  if not current_index then
    logger.log('current problem not found in contest', vim.log.levels.ERROR)
    return
  end

  local new_index = current_index + direction
  if new_index < 1 or new_index > #problems then
    logger.log('no more problems in that direction', vim.log.levels.WARN)
    return
  end

  local new_problem = problems[new_index]
  M.setup_problem(contest_id, new_problem.id, language)

  state.set_problem_id(new_problem.id)
end

return M
