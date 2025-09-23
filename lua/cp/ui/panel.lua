local M = {}

local buffer_utils = require('cp.utils.buffer')
local config_module = require('cp.config')
local layouts = require('cp.ui.layouts')
local logger = require('cp.log')
local problem = require('cp.problem')
local state = require('cp.state')

local current_diff_layout = nil
local current_mode = nil

local function get_current_problem()
  return state.get_problem_id()
end

function M.toggle_run_panel(is_debug)
  if state.is_run_panel_active() then
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

    state.set_run_panel_active(false)
    logger.log('test panel closed')
    return
  end

  if not state.get_platform() then
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

  local platform = state.get_platform()
  local contest_id = state.get_contest_id()

  logger.log(
    ('run panel: platform=%s, contest=%s, problem=%s'):format(
      platform or 'nil',
      contest_id or 'nil',
      problem_id or 'nil'
    )
  )

  local config = config_module.get_config()
  local ctx = problem.create_context(platform or '', contest_id or '', problem_id, config)
  local run = require('cp.runner.run')

  logger.log(('run panel: checking test cases for %s'):format(ctx.input_file))

  if not run.load_test_cases(ctx, state) then
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

  local test_windows = {
    tab_win = main_win,
  }
  local test_buffers = {
    tab_buf = tab_buf,
  }

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

    test_state.current_index = test_state.current_index + delta
    if test_state.current_index < 1 then
      test_state.current_index = #test_state.test_cases
    elseif test_state.current_index > #test_state.test_cases then
      test_state.current_index = 1
    end

    refresh_run_panel()
  end

  setup_keybindings_for_buffer = function(buf)
    vim.keymap.set('n', 'q', function()
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

  if config.hooks and config.hooks.before_run then
    config.hooks.before_run(ctx)
  end

  if is_debug and config.hooks and config.hooks.before_debug then
    config.hooks.before_debug(ctx)
  end

  local execute = require('cp.runner.execute')
  local contest_config = config.contests[state.get_platform() or '']
  local compile_result = execute.compile_problem(ctx, contest_config, is_debug)
  if compile_result.success then
    run.run_all_test_cases(ctx, contest_config, config)
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

  state.set_run_panel_active(true)
  state.test_buffers = test_buffers
  state.test_windows = test_windows
  local test_state = run.get_run_panel_state()
  logger.log(
    string.format('test panel opened (%d test cases)', #test_state.test_cases),
    vim.log.levels.INFO
  )
end

return M
