local M = {}

local cache = require('cp.cache')
local config_module = require('cp.config')
local logger = require('cp.log')
local problem = require('cp.problem')
local scrape = require('cp.scrape')
local snippets = require('cp.snippets')
local state = require('cp.state')

local constants = require('cp.constants')
local platforms = constants.PLATFORMS

function M.set_platform(platform)
  if not vim.tbl_contains(platforms, platform) then
    logger.log(
      ('unknown platform. Available: [%s]'):format(table.concat(platforms, ', ')),
      vim.log.levels.ERROR
    )
    return false
  end

  state.set_platform(platform)
  vim.system({ 'mkdir', '-p', 'build', 'io' }):wait()
  return true
end

function M.setup_problem(contest_id, problem_id, language)
  if not state.get_platform() then
    logger.log('no platform set. run :CP <platform> <contest> first', vim.log.levels.ERROR)
    return
  end

  local config = config_module.get_config()
  local problem_name = contest_id .. (problem_id or '')
  logger.log(('setting up problem: %s'):format(problem_name))

  local ctx =
    problem.create_context(state.get_platform() or '', contest_id, problem_id, config, language)

  if vim.tbl_contains(config.scrapers, state.get_platform() or '') then
    cache.load()
    local existing_contest_data = cache.get_contest_data(state.get_platform() or '', contest_id)

    if not existing_contest_data then
      local metadata_result = scrape.scrape_contest_metadata(state.get_platform() or '', contest_id)
      if not metadata_result.success then
        logger.log(
          'failed to load contest metadata: ' .. (metadata_result.error or 'unknown error'),
          vim.log.levels.WARN
        )
      end
    end
  end

  local cached_test_cases = cache.get_test_cases(state.get_platform() or '', contest_id, problem_id)
  if cached_test_cases then
    state.set_test_cases(cached_test_cases)
    logger.log(('using cached test cases (%d)'):format(#cached_test_cases))
  elseif vim.tbl_contains(config.scrapers, state.get_platform() or '') then
    local platform_display_name = constants.PLATFORM_DISPLAY_NAMES[state.get_platform() or '']
      or (state.get_platform() or '')
    logger.log(
      ('Scraping %s %s %s for test cases, this may take a few seconds...'):format(
        platform_display_name,
        contest_id,
        problem_id
      ),
      vim.log.levels.INFO,
      true
    )

    local scrape_result = scrape.scrape_problem(ctx)

    if not scrape_result.success then
      logger.log(
        'scraping failed: ' .. (scrape_result.error or 'unknown error'),
        vim.log.levels.ERROR
      )
      return
    end

    local test_count = scrape_result.test_count or 0
    logger.log(('scraped %d test case(s) for %s'):format(test_count, scrape_result.problem_id))
    state.set_test_cases(scrape_result.test_cases)

    if scrape_result.test_cases then
      cache.set_test_cases(
        state.get_platform() or '',
        contest_id,
        problem_id,
        scrape_result.test_cases
      )
    end
  else
    logger.log(('scraping disabled for %s'):format(state.get_platform() or ''))
    state.set_test_cases(nil)
  end

  vim.cmd('silent only')
  state.set_run_panel_active(false)

  state.set_contest_id(contest_id)
  state.set_problem_id(problem_id)

  vim.cmd.e(ctx.source_file)
  local source_buf = vim.api.nvim_get_current_buf()

  if vim.api.nvim_buf_get_lines(source_buf, 0, -1, true)[1] == '' then
    local has_luasnip, luasnip = pcall(require, 'luasnip')
    if has_luasnip then
      local filetype = vim.api.nvim_get_option_value('filetype', { buf = source_buf })
      local language_name = constants.filetype_to_language[filetype]
      local canonical_language = constants.canonical_filetypes[language_name] or language_name
      local prefixed_trigger = ('cp.nvim/%s.%s'):format(state.get_platform(), canonical_language)

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
      vim.api.nvim_input(('i%s<c-space><esc>'):format(state.get_platform()))
    end
  end

  if config.hooks and config.hooks.setup_code then
    config.hooks.setup_code(ctx)
  end

  cache.set_file_state(
    vim.fn.expand('%:p'),
    state.get_platform() or '',
    contest_id,
    problem_id,
    language
  )

  logger.log(('switched to problem %s'):format(ctx.problem_name))
end

function M.setup_contest(contest_id, language)
  if not state.get_platform() then
    logger.log('no platform set', vim.log.levels.ERROR)
    return false
  end

  local config = config_module.get_config()

  if not vim.tbl_contains(config.scrapers, state.get_platform() or '') then
    logger.log('scraping disabled for ' .. (state.get_platform() or ''), vim.log.levels.WARN)
    return false
  end

  logger.log(('setting up contest %s %s'):format(state.get_platform() or '', contest_id))

  local metadata_result = scrape.scrape_contest_metadata(state.get_platform() or '', contest_id)
  if not metadata_result.success then
    logger.log(
      'failed to load contest metadata: ' .. (metadata_result.error or 'unknown error'),
      vim.log.levels.ERROR
    )
    return false
  end

  local problems = metadata_result.problems
  if not problems or #problems == 0 then
    logger.log('no problems found in contest', vim.log.levels.ERROR)
    return false
  end

  logger.log(('found %d problems, checking cache...'):format(#problems))

  cache.load()
  local missing_problems = {}
  for _, prob in ipairs(problems) do
    local cached_tests = cache.get_test_cases(state.get_platform() or '', contest_id, prob.id)
    if not cached_tests then
      table.insert(missing_problems, prob)
    end
  end

  if #missing_problems > 0 then
    local contest_scraper = require('cp.setup.contest')
    contest_scraper.scrape_missing_problems(contest_id, missing_problems, config)
  else
    logger.log('all problems already cached')
  end

  state.set_contest_id(contest_id)
  M.setup_problem(contest_id, problems[1].id, language)

  return true
end

function M.navigate_problem(delta, language)
  if not state.get_platform() or not state.get_contest_id() then
    logger.log('no contest set. run :CP <platform> <contest> first', vim.log.levels.ERROR)
    return
  end

  local navigation = require('cp.setup.navigation')
  navigation.navigate_problem(delta, language)
end

function M.handle_full_setup(cmd)
  state.set_contest_id(cmd.contest)
  local problem_ids = {}
  local has_metadata = false
  local config = config_module.get_config()

  if vim.tbl_contains(config.scrapers, cmd.platform) then
    local metadata_result = scrape.scrape_contest_metadata(cmd.platform, cmd.contest)
    if not metadata_result.success then
      logger.log(
        'failed to load contest metadata: ' .. (metadata_result.error or 'unknown error'),
        vim.log.levels.ERROR
      )
      return
    end

    logger.log(
      ('loaded %d problems for %s %s'):format(#metadata_result.problems, cmd.platform, cmd.contest),
      vim.log.levels.INFO,
      true
    )
    problem_ids = vim.tbl_map(function(prob)
      return prob.id
    end, metadata_result.problems)
    has_metadata = true
  else
    cache.load()
    local contest_data = cache.get_contest_data(cmd.platform or '', cmd.contest)
    if contest_data and contest_data.problems then
      problem_ids = vim.tbl_map(function(prob)
        return prob.id
      end, contest_data.problems)
      has_metadata = true
    end
  end

  if has_metadata and not vim.tbl_contains(problem_ids, cmd.problem) then
    logger.log(
      ("Invalid problem '%s' for contest %s %s"):format(cmd.problem, cmd.platform, cmd.contest),
      vim.log.levels.ERROR
    )
    return
  end

  M.setup_problem(cmd.contest, cmd.problem, cmd.language)
end

return M
