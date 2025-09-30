local M = {}

local buffer_utils = require('cp.utils.buffer')
local config_module = require('cp.config')
local layouts = require('cp.ui.layouts')
local logger = require('cp.log')
local state = require('cp.state')

local current_diff_layout = nil
local current_mode = nil

function M.toggle_interactive()
  if state.get_active_panel() == 'interactive' then
    if state.interactive_buf and vim.api.nvim_buf_is_valid(state.interactive_buf) then
      local job = vim.b[state.interactive_buf].terminal_job_id
      if job then
        vim.fn.jobstop(job)
      end
    end
    if state.saved_interactive_session then
      vim.cmd(('source %s'):format(state.saved_interactive_session))
      vim.fn.delete(state.saved_interactive_session)
      state.saved_interactive_session = nil
    end
    state.set_active_panel(nil)
    logger.log('interactive closed')
    return
  end

  if state.get_active_panel() then
    logger.log('another panel is already active', vim.log.levels.ERROR)
    return
  end

  local platform, contest_id = state.get_platform(), state.get_contest_id()

  if not platform then
    logger.log(
      'No platform configured. Use :CP <platform> <contest> [...] first.',
      vim.log.levels.ERROR
    )
    return
  end

  if not contest_id then
    logger.log(
      ('No contest %s configured for platform %s. Use :CP <platform> <contest> <problem> to set up first.'):format(
        contest_id,
        platform
      ),
      vim.log.levels.ERROR
    )
    return
  end

  local problem_id = state.get_problem_id()
  if not problem_id then
    logger.log(('No problem found for the current problem id %s'):format(problem_id))
    return
  end

  local cache = require('cp.cache')
  cache.load()
  local contest_data = cache.get_contest_data(platform, contest_id)
  if contest_data and not contest_data.interactive then
    logger.log(
      'This is NOT an interactive problem. Use :CP run instead - aborting.',
      vim.log.levels.WARN
    )
    return
  end

  state.saved_interactive_session = vim.fn.tempname()
  vim.cmd(('mksession! %s'):format(state.saved_interactive_session))
  vim.cmd('silent only')

  local config = config_module.get_config()
  local contest_config = config.contests[state.get_platform() or '']
  local execute = require('cp.runner.execute')
  local compile_result = execute.compile_problem(contest_config, false)
  if not compile_result.success then
    require('cp.runner.run').handle_compilation_failure(compile_result.output)
    return
  end

  local binary = state.get_binary_file()
  if not binary then
    logger.log('no binary path found', vim.log.levels.ERROR)
    return
  end

  vim.cmd('terminal')
  local term_buf = vim.api.nvim_get_current_buf()
  local term_win = vim.api.nvim_get_current_win()

  vim.fn.chansend(vim.b.terminal_job_id, binary .. '\n')

  vim.keymap.set('t', config.run_panel.close_key, function()
    M.toggle_interactive()
  end, { buffer = term_buf, silent = true })

  state.interactive_buf = term_buf
  state.interactive_win = term_win
  state.set_active_panel('interactive')
  logger.log(('interactive opened, running %s'):format(binary))
end

function M.toggle_run_panel(is_debug)
  if state.get_active_panel() == 'run' then
    if current_diff_layout then
      current_diff_layout.cleanup()
      current_diff_layout = nil
      current_mode = nil
    end
    if state.saved_session then
      vim.cmd(('source %s'):format(state.saved_session))
      vim.fn.delete(state.saved_session)
      state.saved_session = nil
    end
    state.set_active_panel(nil)
    logger.log('test panel closed')
    return
  end

  if state.get_active_panel() then
    logger.log('another panel is already active', vim.log.levels.ERROR)
    return
  end

  local platform, contest_id = state.get_platform(), state.get_contest_id()

  if not platform then
    logger.log(
      'No platform configured. Use :CP <platform> <contest> [...] first.',
      vim.log.levels.ERROR
    )
    return
  end

  if not contest_id then
    logger.log(
      ('No contest %s configured for platform %s. Use :CP <platform> <contest> <problem> to set up first.'):format(
        contest_id,
        platform
      ),
      vim.log.levels.ERROR
    )
    return
  end

  local problem_id = state.get_problem_id()
  if not problem_id then
    logger.log(('No problem found for the current problem id %s'):format(problem_id))
    return
  end

  local cache = require('cp.cache')
  cache.load()
  local contest_data = cache.get_contest_data(platform, contest_id)
  if contest_data and contest_data.interactive then
    logger.log(
      'This is an interactive problem. Use :CP interact instead - aborting.',
      vim.log.levels.WARN
    )
    return
  end

  logger.log(
    ('run panel: platform=%s, contest=%s, problem=%s'):format(
      tostring(platform),
      tostring(contest_id),
      tostring(problem_id)
    )
  )

  local config = config_module.get_config()
  if config.hooks and config.hooks.before_run then
    config.hooks.before_run(state)
  end
  if is_debug and config.hooks and config.hooks.before_debug then
    config.hooks.before_debug(state)
  end

  local run = require('cp.runner.run')
  local input_file = state.get_input_file()
  logger.log(('run panel: checking test cases for %s'):format(input_file or 'none'))

  if not run.load_test_cases(state) then
    logger.log('no test cases found', vim.log.levels.WARN)
    return
  end

  state.saved_session = vim.fn.tempname()
  vim.cmd(('mksession! %s'):format(state.saved_session))
  vim.cmd('silent only')

  local tab_buf = buffer_utils.create_buffer_with_options()
  local main_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(main_win, tab_buf)
  vim.api.nvim_set_option_value('filetype', 'cptest', { buf = tab_buf })

  local test_windows = { tab_win = main_win }
  local test_buffers = { tab_buf = tab_buf }
  local test_list_namespace = vim.api.nvim_create_namespace('cp_test_list')

  local setup_keybindings_for_buffer

  local function update_diff_panes()
    current_diff_layout, current_mode = layouts.update_diff_panes(
      current_diff_layout,
      current_mode,
      main_win,
      run,
      config,
      setup_keybindings_for_buffer
    )
  end

  local function refresh_run_panel()
    if not test_buffers.tab_buf or not vim.api.nvim_buf_is_valid(test_buffers.tab_buf) then
      return
    end
    local run_render = require('cp.runner.run_render')
    run_render.setup_highlights()
    local test_state = run.get_run_panel_state()
    local tab_lines, tab_highlights = run_render.render_test_list(test_state)
    buffer_utils.update_buffer_content(
      test_buffers.tab_buf,
      tab_lines,
      tab_highlights,
      test_list_namespace
    )
    update_diff_panes()
  end

  local function navigate_test_case(delta)
    local test_state = run.get_run_panel_state()
    if #test_state.test_cases == 0 then
      return
    end
    test_state.current_index = (test_state.current_index + delta) % #test_state.test_cases
    refresh_run_panel()
  end

  setup_keybindings_for_buffer = function(buf)
    vim.keymap.set('n', config.run_panel.close_key, function()
      M.toggle_run_panel()
    end, { buffer = buf, silent = true })
    vim.keymap.set('n', config.run_panel.toggle_diff_key, function()
      local modes = { 'none', 'git', 'vim' }
      local current_idx = nil
      for i, mode in ipairs(modes) do
        if config.run_panel.diff_mode == mode then
          current_idx = i
          break
        end
      end
      current_idx = current_idx or 1
      config.run_panel.diff_mode = modes[(current_idx % #modes) + 1]
      refresh_run_panel()
    end, { buffer = buf, silent = true })
    vim.keymap.set('n', config.run_panel.next_test_key, function()
      navigate_test_case(1)
    end, { buffer = buf, silent = true })
    vim.keymap.set('n', config.run_panel.prev_test_key, function()
      navigate_test_case(-1)
    end, { buffer = buf, silent = true })
  end

  vim.keymap.set('n', config.run_panel.next_test_key, function()
    navigate_test_case(1)
  end, { buffer = test_buffers.tab_buf, silent = true })
  vim.keymap.set('n', config.run_panel.prev_test_key, function()
    navigate_test_case(-1)
  end, { buffer = test_buffers.tab_buf, silent = true })

  setup_keybindings_for_buffer(test_buffers.tab_buf)

  local execute = require('cp.runner.execute')
  local contest_config = config.contests[state.get_platform() or '']
  local compile_result = execute.compile_problem(contest_config, is_debug)
  if compile_result.success then
    run.run_all_test_cases(contest_config, config)
  else
    run.handle_compilation_failure(compile_result.output)
  end

  refresh_run_panel()

  vim.schedule(function()
    if config.run_panel.ansi then
      local ansi = require('cp.ui.ansi')
      ansi.setup_highlight_groups()
    end
    if current_diff_layout then
      update_diff_panes()
    end
  end)

  vim.api.nvim_set_current_win(test_windows.tab_win)
  state.test_buffers = test_buffers
  state.test_windows = test_windows
  state.set_active_panel('run')
  local test_state = run.get_run_panel_state()
  logger.log(
    string.format('test panel opened (%d test cases)', #test_state.test_cases),
    vim.log.levels.INFO
  )
end

return M
