local M = {}

local cache = require('cp.cache')
local config_module = require('cp.config')
local logger = require('cp.log')
local problem = require('cp.problem')
local scrape = require('cp.scrape')
local snippets = require('cp.snippets')

if not vim.fn.has('nvim-0.10.0') then
  vim.notify('[cp.nvim]: requires nvim-0.10.0+', vim.log.levels.ERROR)
  return {}
end

local user_config = {}
local config = config_module.setup(user_config)
logger.set_config(config)
local snippets_initialized = false

local state = {
  platform = nil,
  contest_id = nil,
  problem_id = nil,
  saved_layout = nil,
  saved_session = nil,
  test_cases = nil,
  test_states = {},
  test_panel_active = false,
}

local constants = require('cp.constants')
local platforms = constants.PLATFORMS
local actions = constants.ACTIONS

local function set_platform(platform)
  if not vim.tbl_contains(platforms, platform) then
    logger.log(
      ('unknown platform. Available: [%s]'):format(table.concat(platforms, ', ')),
      vim.log.levels.ERROR
    )
    return false
  end

  state.platform = platform
  vim.fn.mkdir('build', 'p')
  vim.fn.mkdir('io', 'p')
  return true
end

---@param contest_id string
---@param problem_id? string
---@param language? string
local function setup_problem(contest_id, problem_id, language)
  if not state.platform then
    logger.log('no platform set. run :CP <platform> <contest> first', vim.log.levels.ERROR)
    return
  end

  local problem_name = state.platform == 'cses' and contest_id or (contest_id .. (problem_id or ''))
  logger.log(('setting up problem: %s'):format(problem_name))

  local ctx = problem.create_context(state.platform, contest_id, problem_id, config, language)

  if vim.tbl_contains(config.scrapers, state.platform) then
    local metadata_result = scrape.scrape_contest_metadata(state.platform, contest_id)
    if not metadata_result.success then
      logger.log(
        'failed to load contest metadata: ' .. (metadata_result.error or 'unknown error'),
        vim.log.levels.WARN
      )
    end
  end

  local cached_test_cases = cache.get_test_cases(state.platform, contest_id, problem_id)
  if cached_test_cases then
    state.test_cases = cached_test_cases
  end

  if vim.tbl_contains(config.scrapers, state.platform) then
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
    state.test_cases = scrape_result.test_cases

    if scrape_result.test_cases then
      cache.set_test_cases(state.platform, contest_id, problem_id, scrape_result.test_cases)
    end
  else
    logger.log(('scraping disabled for %s'):format(state.platform))
    state.test_cases = nil
  end

  vim.cmd('silent only')

  state.contest_id = contest_id
  state.problem_id = problem_id

  vim.cmd.e(ctx.source_file)
  local source_buf = vim.api.nvim_get_current_buf()

  if vim.api.nvim_buf_get_lines(source_buf, 0, -1, true)[1] == '' then
    local has_luasnip, luasnip = pcall(require, 'luasnip')
    if has_luasnip then
      local filetype = vim.api.nvim_get_option_value('filetype', { buf = source_buf })
      local language_name = constants.filetype_to_language[filetype]
      local canonical_language = constants.canonical_filetypes[language_name] or language_name
      local prefixed_trigger = ('cp.nvim/%s.%s'):format(state.platform, canonical_language)

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
      vim.api.nvim_input(('i%s<c-space><esc>'):format(state.platform))
    end
  end

  if config.hooks and config.hooks.setup_code then
    config.hooks.setup_code(ctx)
  end

  logger.log(('switched to problem %s'):format(ctx.problem_name))
end

local function get_current_problem()
  local filename = vim.fn.expand('%:t:r')
  if filename == '' then
    logger.log('no file open', vim.log.levels.ERROR)
    return nil
  end
  return filename
end

local function toggle_test_panel(is_debug)
  if state.test_panel_active then
    if state.saved_session then
      vim.cmd(('source %s'):format(state.saved_session))
      vim.fn.delete(state.saved_session)
      state.saved_session = nil
    end
    state.test_panel_active = false
    logger.log('test panel closed')
    return
  end

  if not state.platform then
    logger.log(
      'No contest configured. Use :CP <platform> <contest> <problem> to set up first.',
      vim.log.levels.ERROR
    )
    return
  end

  local problem_id = get_current_problem()
  if not problem_id then
    return
  end

  local ctx = problem.create_context(state.platform, state.contest_id, state.problem_id, config)
  local test_module = require('cp.test')

  if not test_module.load_test_cases(ctx, state) then
    logger.log('no test cases found', vim.log.levels.WARN)
    return
  end

  state.saved_session = vim.fn.tempname()
  vim.cmd(('mksession! %s'):format(state.saved_session))

  vim.cmd('silent only')

  local tab_buf = vim.api.nvim_create_buf(false, true)
  local expected_buf = vim.api.nvim_create_buf(false, true)
  local actual_buf = vim.api.nvim_create_buf(false, true)

  -- Set buffer options
  for _, buf in ipairs({ tab_buf, expected_buf, actual_buf }) do
    vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = buf })
    vim.api.nvim_set_option_value('readonly', true, { buf = buf })
    vim.api.nvim_set_option_value('modifiable', false, { buf = buf })
  end

  local main_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(main_win, tab_buf)
  vim.api.nvim_set_option_value('filetype', 'cptest', { buf = tab_buf })

  vim.cmd.split()
  vim.api.nvim_win_set_buf(0, actual_buf)
  vim.api.nvim_set_option_value('filetype', 'cptest', { buf = actual_buf })

  vim.cmd.vsplit()
  vim.api.nvim_win_set_buf(0, expected_buf)
  vim.api.nvim_set_option_value('filetype', 'cptest', { buf = expected_buf })

  local expected_win = vim.fn.bufwinid(expected_buf)
  local actual_win = vim.fn.bufwinid(actual_buf)

  local test_windows = {
    tab_win = main_win,
    actual_win = actual_win,
    expected_win = expected_win,
  }
  local test_buffers = {
    tab_buf = tab_buf,
    expected_buf = expected_buf,
    actual_buf = actual_buf,
  }

  local highlight = require('cp.highlight')
  local diff_namespace = highlight.create_namespace()

  local test_list_namespace = vim.api.nvim_create_namespace('cp_test_list')

  local function update_buffer_content(bufnr, lines, highlights)
    local was_readonly = vim.api.nvim_get_option_value('readonly', { buf = bufnr })

    vim.api.nvim_set_option_value('readonly', false, { buf = bufnr })
    vim.api.nvim_set_option_value('modifiable', true, { buf = bufnr })
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    vim.api.nvim_set_option_value('modifiable', false, { buf = bufnr })
    vim.api.nvim_set_option_value('readonly', was_readonly, { buf = bufnr })

    vim.api.nvim_buf_clear_namespace(bufnr, test_list_namespace, 0, -1)
    for _, highlight in ipairs(highlights) do
      vim.api.nvim_buf_set_extmark(
        bufnr,
        test_list_namespace,
        highlight.line,
        highlight.col_start,
        {
          end_col = highlight.col_end,
          hl_group = highlight.highlight_group,
          priority = 100,
        }
      )
    end
  end

  local function update_expected_pane()
    local test_state = test_module.get_test_panel_state()
    local current_test = test_state.test_cases[test_state.current_index]

    if not current_test then
      return
    end

    local expected_text = current_test.expected
    local expected_lines = vim.split(expected_text, '\n', { plain = true, trimempty = true })

    update_buffer_content(test_buffers.expected_buf, expected_lines, {})

    local diff_backend = require('cp.diff')
    local backend = diff_backend.get_best_backend(config.test_panel.diff_mode)

    if backend.name == 'vim' and current_test.status == 'fail' then
      vim.api.nvim_set_option_value('diff', true, { win = test_windows.expected_win })
    else
      vim.api.nvim_set_option_value('diff', false, { win = test_windows.expected_win })
    end
  end

  local function update_actual_pane()
    local test_state = test_module.get_test_panel_state()
    local current_test = test_state.test_cases[test_state.current_index]

    if not current_test then
      return
    end

    local actual_lines = {}
    local enable_diff = false

    if current_test.actual then
      actual_lines = vim.split(current_test.actual, '\n', { plain = true, trimempty = true })
      enable_diff = current_test.status == 'fail'
    else
      actual_lines = { '(not run yet)' }
    end

    if enable_diff then
      local diff_backend = require('cp.diff')
      local backend = diff_backend.get_best_backend(config.test_panel.diff_mode)

      if backend.name == 'git' then
        local diff_result = backend.render(current_test.expected, current_test.actual)
        if diff_result.raw_diff and diff_result.raw_diff ~= '' then
          highlight.parse_and_apply_diff(
            test_buffers.actual_buf,
            diff_result.raw_diff,
            diff_namespace
          )
        else
          update_buffer_content(test_buffers.actual_buf, actual_lines, {})
        end
      else
        update_buffer_content(test_buffers.actual_buf, actual_lines, {})
        vim.api.nvim_set_option_value('diff', true, { win = test_windows.actual_win })
        vim.api.nvim_win_call(test_windows.expected_win, function()
          vim.cmd.diffthis()
        end)
        vim.api.nvim_win_call(test_windows.actual_win, function()
          vim.cmd.diffthis()
        end)
      end
    else
      update_buffer_content(test_buffers.actual_buf, actual_lines, {})
      vim.api.nvim_set_option_value('diff', false, { win = test_windows.expected_win })
      vim.api.nvim_set_option_value('diff', false, { win = test_windows.actual_win })
    end
  end

  local function refresh_test_panel()
    if not test_buffers.tab_buf or not vim.api.nvim_buf_is_valid(test_buffers.tab_buf) then
      return
    end

    local test_render = require('cp.test_render')
    test_render.setup_highlights()
    local test_state = test_module.get_test_panel_state()
    local tab_lines, tab_highlights = test_render.render_test_list(test_state)
    update_buffer_content(test_buffers.tab_buf, tab_lines, tab_highlights)

    update_expected_pane()
    update_actual_pane()
  end

  local function navigate_test_case(delta)
    local test_state = test_module.get_test_panel_state()
    if #test_state.test_cases == 0 then
      return
    end

    test_state.current_index = test_state.current_index + delta
    if test_state.current_index < 1 then
      test_state.current_index = #test_state.test_cases
    elseif test_state.current_index > #test_state.test_cases then
      test_state.current_index = 1
    end

    refresh_test_panel()
  end

  vim.keymap.set('n', config.test_panel.next_test_key, function()
    navigate_test_case(1)
  end, { buffer = test_buffers.tab_buf, silent = true })
  vim.keymap.set('n', config.test_panel.prev_test_key, function()
    navigate_test_case(-1)
  end, { buffer = test_buffers.tab_buf, silent = true })

  for _, buf in pairs(test_buffers) do
    vim.keymap.set('n', 'q', function()
      toggle_test_panel()
    end, { buffer = buf, silent = true })
    vim.keymap.set('n', config.test_panel.toggle_key, function()
      toggle_test_panel()
    end, { buffer = buf, silent = true })
  end

  if config.hooks and config.hooks.before_test then
    config.hooks.before_test(ctx)
  end

  if is_debug and config.hooks and config.hooks.before_debug then
    config.hooks.before_debug(ctx)
  end

  local execute_module = require('cp.execute')
  local contest_config = config.contests[state.platform]
  if execute_module.compile_problem(ctx, contest_config, is_debug) then
    test_module.run_all_test_cases(ctx, contest_config)
  end

  refresh_test_panel()

  vim.api.nvim_set_current_win(test_windows.tab_win)

  state.test_panel_active = true
  state.test_buffers = test_buffers
  state.test_windows = test_windows
  local test_state = test_module.get_test_panel_state()
  logger.log(string.format('test panel opened (%d test cases)', #test_state.test_cases))
end

---@param delta number 1 for next, -1 for prev
---@param language? string
local function navigate_problem(delta, language)
  if not state.platform or not state.contest_id then
    logger.log('no contest set. run :CP <platform> <contest> first', vim.log.levels.ERROR)
    return
  end

  cache.load()
  local contest_data = cache.get_contest_data(state.platform, state.contest_id)
  if not contest_data or not contest_data.problems then
    logger.log(
      'no contest metadata found. set up a problem first to cache contest data',
      vim.log.levels.ERROR
    )
    return
  end

  local problems = contest_data.problems
  local current_problem_id

  if state.platform == 'cses' then
    current_problem_id = state.contest_id
  else
    current_problem_id = state.problem_id
  end

  if not current_problem_id then
    logger.log('no current problem set', vim.log.levels.ERROR)
    return
  end

  local current_index = nil
  for i, prob in ipairs(problems) do
    if prob.id == current_problem_id then
      current_index = i
      break
    end
  end

  if not current_index then
    logger.log('current problem not found in contest', vim.log.levels.ERROR)
    return
  end

  local new_index = current_index + delta

  if new_index < 1 or new_index > #problems then
    local direction = delta > 0 and 'next' or 'previous'
    logger.log(('no %s problem available'):format(direction), vim.log.levels.INFO)
    return
  end

  local new_problem = problems[new_index]

  if state.platform == 'cses' then
    setup_problem(new_problem.id, nil, language)
  else
    setup_problem(state.contest_id, new_problem.id, language)
  end
end

local function parse_command(args)
  if #args == 0 then
    return {
      type = 'error',
      message = 'Usage: :CP <platform> <contest> [problem] [--lang=<language>] | :CP <action> | :CP <problem>',
    }
  end

  local language = nil
  local debug = false

  for i, arg in ipairs(args) do
    local lang_match = arg:match('^--lang=(.+)$')
    if lang_match then
      language = lang_match
    elseif arg == '--lang' then
      if i + 1 <= #args then
        language = args[i + 1]
      else
        return { type = 'error', message = '--lang requires a value' }
      end
    elseif arg == '--debug' then
      debug = true
    end
  end

  local filtered_args = vim.tbl_filter(function(arg)
    return not (arg:match('^--lang') or arg == language or arg == '--debug')
  end, args)

  local first = filtered_args[1]

  if vim.tbl_contains(actions, first) then
    return { type = 'action', action = first, language = language, debug = debug }
  end

  if vim.tbl_contains(platforms, first) then
    if #filtered_args == 1 then
      return {
        type = 'platform_only',
        platform = first,
        language = language,
      }
    elseif #filtered_args == 2 then
      if first == 'cses' then
        return {
          type = 'cses_problem',
          platform = first,
          problem = filtered_args[2],
          language = language,
        }
      else
        return {
          type = 'contest_setup',
          platform = first,
          contest = filtered_args[2],
          language = language,
        }
      end
    elseif #filtered_args == 3 then
      return {
        type = 'full_setup',
        platform = first,
        contest = filtered_args[2],
        problem = filtered_args[3],
        language = language,
      }
    else
      return { type = 'error', message = 'Too many arguments' }
    end
  end

  if state.platform and state.contest_id then
    cache.load()
    local contest_data = cache.get_contest_data(state.platform, state.contest_id)
    if contest_data and contest_data.problems then
      local problem_ids = vim.tbl_map(function(prob)
        return prob.id
      end, contest_data.problems)
      if vim.tbl_contains(problem_ids, first) then
        return { type = 'problem_switch', problem = first, language = language }
      end
    end
    return {
      type = 'error',
      message = ("invalid subcommand '%s'"):format(first),
    }
  end

  return { type = 'error', message = 'Unknown command or no contest context' }
end

function M.handle_command(opts)
  local cmd = parse_command(opts.fargs)

  if cmd.type == 'error' then
    logger.log(cmd.message, vim.log.levels.ERROR)
    return
  end

  if cmd.type == 'action' then
    if cmd.action == 'test' then
      toggle_test_panel(cmd.debug)
    elseif cmd.action == 'next' then
      navigate_problem(1, cmd.language)
    elseif cmd.action == 'prev' then
      navigate_problem(-1, cmd.language)
    end
    return
  end

  if cmd.type == 'platform_only' then
    set_platform(cmd.platform)
    return
  end

  if cmd.type == 'contest_setup' then
    if set_platform(cmd.platform) then
      state.contest_id = cmd.contest
      if vim.tbl_contains(config.scrapers, cmd.platform) then
        local metadata_result = scrape.scrape_contest_metadata(cmd.platform, cmd.contest)
        if not metadata_result.success then
          logger.log(
            'failed to load contest metadata: ' .. (metadata_result.error or 'unknown error'),
            vim.log.levels.WARN
          )
        else
          logger.log(
            ('loaded %d problems for %s %s'):format(
              #metadata_result.problems,
              cmd.platform,
              cmd.contest
            )
          )
        end
      end
    end
    return
  end

  if cmd.type == 'full_setup' then
    if set_platform(cmd.platform) then
      state.contest_id = cmd.contest
      local problem_ids = {}
      local has_metadata = false

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
          ('loaded %d problems for %s %s'):format(
            #metadata_result.problems,
            cmd.platform,
            cmd.contest
          )
        )
        problem_ids = vim.tbl_map(function(prob)
          return prob.id
        end, metadata_result.problems)
        has_metadata = true
      else
        cache.load()
        local contest_data = cache.get_contest_data(cmd.platform, cmd.contest)
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

      setup_problem(cmd.contest, cmd.problem, cmd.language)
    end
    return
  end

  if cmd.type == 'cses_problem' then
    if set_platform(cmd.platform) then
      if vim.tbl_contains(config.scrapers, cmd.platform) then
        local metadata_result = scrape.scrape_contest_metadata(cmd.platform, '')
        if not metadata_result.success then
          logger.log(
            'failed to load contest metadata: ' .. (metadata_result.error or 'unknown error'),
            vim.log.levels.WARN
          )
        end
      end
      setup_problem(cmd.problem, nil, cmd.language)
    end
    return
  end

  if cmd.type == 'problem_switch' then
    if state.platform == 'cses' then
      setup_problem(cmd.problem, nil, cmd.language)
    else
      setup_problem(state.contest_id, cmd.problem, cmd.language)
    end
    return
  end
end

function M.setup(opts)
  opts = opts or {}
  user_config = opts
  config = config_module.setup(user_config)
  logger.set_config(config)
  if not snippets_initialized then
    snippets.setup(config)
    snippets_initialized = true
  end
end

function M.get_current_context()
  return {
    platform = state.platform,
    contest_id = state.contest_id,
    problem_id = state.problem_id,
  }
end

function M.is_initialized()
  return true
end

return M
