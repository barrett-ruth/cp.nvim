local M = {}

---@class RunOpts
---@field debug? boolean

local config_module = require('cp.config')
local layouts = require('cp.ui.layouts')
local logger = require('cp.log')
local state = require('cp.state')
local utils = require('cp.utils')

local current_diff_layout = nil
local current_mode = nil

function M.disable()
  local active_panel = state.get_active_panel()
  if not active_panel then
    logger.log('No active panel to close')
    return
  end

  if active_panel == 'run' then
    M.toggle_run_panel()
  elseif active_panel == 'interactive' then
    M.toggle_interactive()
  else
    logger.log(('Unknown panel type: %s'):format(tostring(active_panel)))
  end
end

---@param interactor_cmd? string
function M.toggle_interactive(interactor_cmd)
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
    return
  end

  if state.get_active_panel() then
    logger.log('Another panel is already active.', vim.log.levels.WARN)
    return
  end

  local platform, contest_id = state.get_platform(), state.get_contest_id()
  if not platform then
    logger.log('No platform configured.', vim.log.levels.ERROR)
    return
  end
  if not contest_id then
    logger.log(
      ('No contest %s configured for platform %s.'):format(contest_id, platform),
      vim.log.levels.ERROR
    )
    return
  end

  local problem_id = state.get_problem_id()
  if not problem_id then
    logger.log('No problem is active.', vim.log.levels.ERROR)
    return
  end

  local cache = require('cp.cache')
  cache.load()
  local contest_data = cache.get_contest_data(platform, contest_id)
  if
    not contest_data
    or not contest_data.index_map
    or not contest_data.problems[contest_data.index_map[problem_id]]
    or not contest_data.problems[contest_data.index_map[problem_id]].interactive
  then
    logger.log('This problem is not interactive. Use :CP run.', vim.log.levels.ERROR)
    return
  end

  state.saved_interactive_session = vim.fn.tempname()
  vim.cmd(('mksession! %s'):format(state.saved_interactive_session))
  vim.cmd('silent only')

  local execute = require('cp.runner.execute')
  local compile_result = execute.compile_problem()
  if not compile_result.success then
    require('cp.runner.run').handle_compilation_failure(compile_result.output)
    return
  end

  local binary = state.get_binary_file()
  if not binary or binary == '' then
    logger.log('No binary produced.', vim.log.levels.ERROR)
    return
  end

  local cmdline
  if interactor_cmd and interactor_cmd ~= '' then
    local interactor = interactor_cmd
    if not interactor:find('/') then
      interactor = './' .. interactor
    end
    if vim.fn.executable(interactor) ~= 1 then
      logger.log(('Interactor not executable: %s'):format(interactor_cmd), vim.log.levels.ERROR)
      if state.saved_interactive_session then
        vim.cmd(('source %s'):format(state.saved_interactive_session))
        vim.fn.delete(state.saved_interactive_session)
        state.saved_interactive_session = nil
      end
      return
    end
    local orchestrator = vim.fn.fnamemodify(utils.get_plugin_path() .. '/scripts/interact.py', ':p')
    cmdline = table.concat({
      'uv',
      'run',
      vim.fn.shellescape(orchestrator),
      vim.fn.shellescape(interactor),
      vim.fn.shellescape(binary),
    }, ' ')
  else
    cmdline = vim.fn.shellescape(binary)
  end

  vim.cmd('terminal ' .. cmdline)
  local term_buf = vim.api.nvim_get_current_buf()
  local term_win = vim.api.nvim_get_current_win()

  local cleaned = false
  local function cleanup()
    if cleaned then
      return
    end
    cleaned = true
    if term_buf and vim.api.nvim_buf_is_valid(term_buf) then
      local job = vim.b[term_buf] and vim.b[term_buf].terminal_job_id or nil
      if job then
        pcall(vim.fn.jobstop, job)
      end
    end
    if state.saved_interactive_session then
      vim.cmd(('source %s'):format(state.saved_interactive_session))
      vim.fn.delete(state.saved_interactive_session)
      state.saved_interactive_session = nil
    end
    state.interactive_buf = nil
    state.interactive_win = nil
    state.set_active_panel(nil)
  end

  vim.api.nvim_create_autocmd({ 'BufWipeout', 'BufUnload' }, {
    buffer = term_buf,
    callback = function()
      cleanup()
    end,
  })

  vim.api.nvim_create_autocmd('WinClosed', {
    callback = function()
      if cleaned then
        return
      end
      local any = false
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == term_buf then
          any = true
          break
        end
      end
      if not any then
        cleanup()
      end
    end,
  })

  vim.api.nvim_create_autocmd('TermClose', {
    buffer = term_buf,
    callback = function()
      vim.b[term_buf].cp_interactive_exited = true
    end,
  })

  vim.keymap.set('t', '<c-q>', function()
    cleanup()
  end, { buffer = term_buf, silent = true })
  vim.keymap.set('n', '<c-q>', function()
    cleanup()
  end, { buffer = term_buf, silent = true })

  state.interactive_buf = term_buf
  state.interactive_win = term_win
  state.set_active_panel('interactive')
end

---@param run_opts? RunOpts
function M.toggle_run_panel(run_opts)
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
      ('No contest %s configured for platform %s.'):format(contest_id, platform),
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
  if
    contest_data
    and contest_data.problems[contest_data.index_map[state.get_problem_id()]].interactive
  then
    logger.log('This is an interactive problem. Use :CP interact instead.', vim.log.levels.WARN)
    return
  end

  logger.log(
    ('Run panel: platform=%s, contest=%s, problem=%s'):format(
      tostring(platform),
      tostring(contest_id),
      tostring(problem_id)
    )
  )

  local config = config_module.get_config()
  local run = require('cp.runner.run')
  local input_file = state.get_input_file()
  logger.log(('run panel: checking test cases for %s'):format(input_file or 'none'))

  if not run.load_test_cases() then
    logger.log('no test cases found', vim.log.levels.WARN)
    return
  end

  state.saved_session = vim.fn.tempname()
  vim.cmd(('mksession! %s'):format(state.saved_session))
  vim.cmd('silent only')

  local tab_buf = utils.create_buffer_with_options()
  local main_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(main_win, tab_buf)
  vim.api.nvim_set_option_value('filetype', 'cp', { buf = tab_buf })

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
    utils.update_buffer_content(
      test_buffers.tab_buf,
      tab_lines,
      tab_highlights,
      test_list_namespace
    )
    update_diff_panes()
  end

  local function navigate_test_case(delta)
    local test_state = run.get_run_panel_state()
    if vim.tbl_isempty(test_state.test_cases) then
      return
    end
    test_state.current_index = (test_state.current_index + delta - 1) % #test_state.test_cases + 1
    refresh_run_panel()
  end

  setup_keybindings_for_buffer = function(buf)
    vim.keymap.set('n', 'q', function()
      M.toggle_run_panel()
    end, { buffer = buf, silent = true })
    vim.keymap.set('n', 't', function()
      local modes = { 'none', 'git', 'vim' }
      local current_idx = nil
      for i, mode in ipairs(modes) do
        if config.ui.run_panel.diff_mode == mode then
          current_idx = i
          break
        end
      end
      current_idx = current_idx or 1
      config.ui.run_panel.diff_mode = modes[(current_idx % #modes) + 1]
      refresh_run_panel()
    end, { buffer = buf, silent = true })
    vim.keymap.set('n', '<c-n>', function()
      navigate_test_case(1)
    end, { buffer = buf, silent = true })
    vim.keymap.set('n', '<c-p>', function()
      navigate_test_case(-1)
    end, { buffer = buf, silent = true })
  end

  setup_keybindings_for_buffer(test_buffers.tab_buf)

  if config.hooks and config.hooks.before_run then
    vim.schedule_wrap(function()
      config.hooks.before_run(state)
    end)
  end
  if run_opts and run_opts.debug and config.hooks and config.hooks.before_debug then
    vim.schedule_wrap(function()
      config.hooks.before_debug(state)
    end)
  end

  local execute = require('cp.runner.execute')
  local compile_result = execute.compile_problem()
  if compile_result.success then
    run.run_all_test_cases()
  else
    run.handle_compilation_failure(compile_result.output)
  end

  refresh_run_panel()

  vim.schedule(function()
    if config.ui.run_panel.ansi then
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
  logger.log('test panel opened')
end

return M
