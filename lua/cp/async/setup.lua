local M = {}

local async = require('cp.async')
local async_scraper = require('cp.async.scraper')
local cache = require('cp.cache')
local config_module = require('cp.config')
local logger = require('cp.log')
local problem = require('cp.problem')
local state = require('cp.state')

function M.setup_contest_async(contest_id, language)
  if not state.get_platform() then
    logger.log('no platform set', vim.log.levels.ERROR)
    return
  end

  async.start_contest_operation('contest_setup')

  local config = config_module.get_config()
  local platform = state.get_platform() or ''

  if not vim.tbl_contains(config.scrapers, platform) then
    logger.log('scraping disabled for ' .. platform, vim.log.levels.WARN)
    async.finish_contest_operation()
    return
  end

  logger.log(('setting up contest %s %s'):format(platform, contest_id))

  async_scraper.scrape_contest_metadata_async(platform, contest_id, function(metadata_result)
    if not metadata_result.success then
      logger.log(
        'failed to load contest metadata: ' .. (metadata_result.error or 'unknown error'),
        vim.log.levels.ERROR
      )
      async.finish_contest_operation()
      return
    end

    local problems = metadata_result.problems
    if not problems or #problems == 0 then
      logger.log('no problems found in contest', vim.log.levels.ERROR)
      async.finish_contest_operation()
      return
    end

    logger.log(('found %d problems'):format(#problems))

    state.set_contest_id(contest_id)
    M.setup_problem_async(contest_id, problems[1].id, language)

    M.start_background_problem_scraping(contest_id, problems, config)
  end)
end

function M.setup_problem_async(contest_id, problem_id, language)
  if not state.get_platform() then
    logger.log('no platform set. run :CP <platform> <contest> first', vim.log.levels.ERROR)
    return
  end

  local config = config_module.get_config()
  local problem_name = contest_id .. (problem_id or '')
  logger.log(('setting up problem: %s'):format(problem_name))

  local ctx =
    problem.create_context(state.get_platform() or '', contest_id, problem_id, config, language)

  local cached_test_cases = cache.get_test_cases(state.get_platform() or '', contest_id, problem_id)
  if cached_test_cases then
    state.set_test_cases(cached_test_cases)
    logger.log(('using cached test cases (%d)'):format(#cached_test_cases))
  elseif vim.tbl_contains(config.scrapers, state.get_platform() or '') then
    logger.log('test cases not cached, will scrape in background...')
    state.set_test_cases(nil)

    async_scraper.scrape_problem_async(
      state.get_platform() or '',
      contest_id,
      problem_id,
      function(scrape_result)
        if scrape_result.success then
          local test_count = scrape_result.test_count or 0
          logger.log(
            ('scraped %d test case(s) for %s'):format(test_count, scrape_result.problem_id)
          )
          state.set_test_cases(scrape_result.test_cases)
        else
          logger.log(
            'scraping failed: ' .. (scrape_result.error or 'unknown error'),
            vim.log.levels.ERROR
          )
        end
      end
    )
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
    local constants = require('cp.constants')
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
  async.finish_contest_operation()
end

function M.start_background_problem_scraping(contest_id, problems, config)
  cache.load()
  local platform = state.get_platform() or ''
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

  local success_count = 0
  local failed_problems = {}
  local total_problems = #missing_problems

  for _, prob in ipairs(missing_problems) do
    async_scraper.scrape_problem_async(platform, contest_id, prob.id, function(result)
      if result.success then
        success_count = success_count + 1
      else
        table.insert(failed_problems, prob.id)
      end

      local completed = success_count + #failed_problems
      if completed == total_problems then
        if #failed_problems > 0 then
          logger.log(
            ('background scraping complete: %d/%d successful, failed: %s'):format(
              success_count,
              total_problems,
              table.concat(failed_problems, ', ')
            ),
            vim.log.levels.WARN
          )
        else
          logger.log(
            ('background scraping complete: %d/%d successful'):format(success_count, total_problems)
          )
        end
      end
    end)
  end
end

function M.handle_full_setup_async(cmd)
  async.start_contest_operation('full_setup')

  state.set_contest_id(cmd.contest)
  local config = config_module.get_config()

  if vim.tbl_contains(config.scrapers, cmd.platform) then
    async_scraper.scrape_contest_metadata_async(cmd.platform, cmd.contest, function(metadata_result)
      if not metadata_result.success then
        logger.log(
          'failed to load contest metadata: ' .. (metadata_result.error or 'unknown error'),
          vim.log.levels.ERROR
        )
        async.finish_contest_operation()
        return
      end

      logger.log(
        ('loaded %d problems for %s %s'):format(
          #metadata_result.problems,
          cmd.platform,
          cmd.contest
        ),
        vim.log.levels.INFO,
        true
      )

      local problem_ids = vim.tbl_map(function(prob)
        return prob.id
      end, metadata_result.problems)

      if not vim.tbl_contains(problem_ids, cmd.problem) then
        logger.log(
          ("Invalid problem '%s' for contest %s %s"):format(cmd.problem, cmd.platform, cmd.contest),
          vim.log.levels.ERROR
        )
        async.finish_contest_operation()
        return
      end

      M.setup_problem_async(cmd.contest, cmd.problem, cmd.language)
    end)
  else
    cache.load()
    local contest_data = cache.get_contest_data(cmd.platform or '', cmd.contest)
    if contest_data and contest_data.problems then
      local problem_ids = vim.tbl_map(function(prob)
        return prob.id
      end, contest_data.problems)

      if not vim.tbl_contains(problem_ids, cmd.problem) then
        logger.log(
          ("Invalid problem '%s' for contest %s %s"):format(cmd.problem, cmd.platform, cmd.contest),
          vim.log.levels.ERROR
        )
        async.finish_contest_operation()
        return
      end

      M.setup_problem_async(cmd.contest, cmd.problem, cmd.language)
    else
      logger.log('no contest data available', vim.log.levels.ERROR)
      async.finish_contest_operation()
    end
  end
end

return M
