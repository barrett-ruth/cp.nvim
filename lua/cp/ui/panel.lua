local M = {}

---@class PanelOpts
---@field debug? boolean

local cache = require('cp.cache')
local config_module = require('cp.config')
local helpers = require('cp.helpers')
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
    M.toggle_panel()
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

  local platform, contest_id, problem_id =
    state.get_platform(), state.get_contest_id(), state.get_problem_id()
  if not platform or not contest_id or not problem_id then
    logger.log(
      'No platform/contest/problem configured. Use :CP <platform> <contest> [...] first.',
      vim.log.levels.ERROR
    )
    return
  end

  cache.load()
  local contest_data = cache.get_contest_data(platform, contest_id)
  if
    not contest_data
    or not contest_data.index_map
    or not contest_data.problems[contest_data.index_map[problem_id]].interactive
  then
    logger.log('This problem is interactive. Use :CP interact.', vim.log.levels.ERROR)
    return
  end

  state.saved_interactive_session = vim.fn.tempname()
  vim.cmd(('mksession! %s'):format(state.saved_interactive_session))
  vim.cmd('silent only')

  local execute = require('cp.runner.execute')
  local run = require('cp.runner.run')
  local compile_result = execute.compile_problem()
  if not compile_result.success then
    run.handle_compilation_failure(compile_result.output)
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
      logger.log(
        ("Interactor '%s' is not executable."):format(interactor_cmd),
        vim.log.levels.ERROR
      )
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

function M.ensure_io_view()
  local platform, contest_id, problem_id =
    state.get_platform(), state.get_contest_id(), state.get_problem_id()
  if not platform or not contest_id or not problem_id then
    logger.log(
      'No platform/contest/problem configured. Use :CP <platform> <contest> [...] first.',
      vim.log.levels.ERROR
    )
    return
  end

  cache.load()
  local contest_data = cache.get_contest_data(platform, contest_id)
  if
    contest_data
    and contest_data.index_map
    and contest_data.problems[contest_data.index_map[problem_id]].interactive
  then
    logger.log('This problem is not interactive. Use :CP {run,panel}.', vim.log.levels.ERROR)
    return
  end

  local solution_win = state.get_solution_win()
  local io_state = state.get_io_view_state()
  local output_buf, input_buf, output_win, input_win

  if io_state then
    output_buf = io_state.output_buf
    input_buf = io_state.input_buf
    output_win = io_state.output_win
    input_win = io_state.input_win
  else
    vim.api.nvim_set_current_win(solution_win)

    vim.cmd.vsplit()
    output_win = vim.api.nvim_get_current_win()
    local width = math.floor(vim.o.columns * 0.3)
    vim.api.nvim_win_set_width(output_win, width)
    output_buf = utils.create_buffer_with_options()
    vim.api.nvim_win_set_buf(output_win, output_buf)

    vim.cmd.split()
    input_win = vim.api.nvim_get_current_win()
    input_buf = utils.create_buffer_with_options()
    vim.api.nvim_win_set_buf(input_win, input_buf)

    state.set_io_view_state({
      output_buf = output_buf,
      input_buf = input_buf,
      output_win = output_win,
      input_win = input_win,
    })

    local config = config_module.get_config()
    if config.hooks and config.hooks.setup_io_output then
      pcall(config.hooks.setup_io_output, output_buf, state)
    end

    if config.hooks and config.hooks.setup_io_input then
      pcall(config.hooks.setup_io_input, input_buf, state)
    end
  end

  utils.update_buffer_content(input_buf, {})
  utils.update_buffer_content(output_buf, {})

  local test_cases = cache.get_test_cases(platform, contest_id, problem_id)
  if test_cases and #test_cases > 0 then
    local input_lines = {}
    for _, tc in ipairs(test_cases) do
      for _, line in ipairs(vim.split(tc.input, '\n')) do
        table.insert(input_lines, line)
      end
    end
    utils.update_buffer_content(input_buf, input_lines, nil, nil)
  end

  vim.api.nvim_set_current_win(solution_win)
end

function M.run_io_view(test_index)
  local platform, contest_id, problem_id =
    state.get_platform(), state.get_contest_id(), state.get_problem_id()
  if not platform or not contest_id or not problem_id then
    logger.log(
      'No platform/contest/problem configured. Use :CP <platform> <contest> [...] first.',
      vim.log.levels.ERROR
    )
    return
  end

  cache.load()
  local contest_data = cache.get_contest_data(platform, contest_id)
  if not contest_data or not contest_data.index_map then
    logger.log('No test cases available.', vim.log.levels.ERROR)
    return
  end

  M.ensure_io_view()

  local run = require('cp.runner.run')
  if not run.load_test_cases() then
    logger.log('No test cases available', vim.log.levels.ERROR)
    return
  end

  local test_state = run.get_panel_state()
  local test_indices = {}

  if test_index then
    if test_index < 1 or test_index > #test_state.test_cases then
      logger.log(
        string.format(
          'Test %d does not exist (only %d tests available)',
          test_index,
          #test_state.test_cases
        ),
        vim.log.levels.WARN
      )
      return
    end
    test_indices = { test_index }
  else
    for i = 1, #test_state.test_cases do
      test_indices[i] = i
    end
  end

  local io_state = state.get_io_view_state()
  if not io_state then
    return
  end

  local config = config_module.get_config()

  if config.ui.ansi then
    require('cp.ui.ansi').setup_highlight_groups()
  end

  local execute = require('cp.runner.execute')
  local compile_result = execute.compile_problem()
  if not compile_result.success then
    local ansi = require('cp.ui.ansi')
    local output = compile_result.output or ''
    local lines, highlights

    if config.ui.ansi then
      local parsed = ansi.parse_ansi_text(output)
      lines = parsed.lines
      highlights = parsed.highlights
    else
      lines = vim.split(output:gsub('\027%[[%d;]*[a-zA-Z]', ''), '\n')
      highlights = {}
    end

    local ns = vim.api.nvim_create_namespace('cp_io_view_compile_error')
    utils.update_buffer_content(io_state.output_buf, lines, highlights, ns)
    return
  end

  run.run_all_test_cases(test_indices)

  local run_render = require('cp.runner.run_render')
  run_render.setup_highlights()

  local input_lines = {}
  local output_lines = {}
  local verdict_data = {}

  local widths = { test_num = 0, status = 0, time = 0, memory = 0, exit = 0 }

  for _, idx in ipairs(test_indices) do
    local tc = test_state.test_cases[idx]

    if tc.actual then
      for _, line in ipairs(vim.split(tc.actual, '\n', { plain = true, trimempty = false })) do
        table.insert(output_lines, line)
      end
    end
    if idx < #test_indices then
      table.insert(output_lines, '')
    end

    local status = run_render.get_status_info(tc)

    local time_actual = tc.time_ms and string.format('%.2f', tc.time_ms) or '—'
    local time_limit = test_state.constraints and tostring(test_state.constraints.timeout_ms)
      or '—'
    local time_data = time_actual .. '/' .. time_limit

    local mem_actual = tc.rss_mb and string.format('%.0f', tc.rss_mb) or '—'
    local mem_limit = test_state.constraints
        and string.format('%.0f', test_state.constraints.memory_mb)
      or '—'
    local mem_data = mem_actual .. '/' .. mem_limit

    local exit_code = tc.code or 0
    local signal_name = exit_code >= 128 and require('cp.constants').signal_codes[exit_code] or nil
    local exit_str = signal_name and string.format('%d (%s)', exit_code, signal_name)
      or tostring(exit_code)

    widths.test_num = math.max(widths.test_num, #('Test ' .. idx .. ':'))
    widths.status = math.max(widths.status, #status.text)
    widths.time = math.max(widths.time, #(time_data .. ' ms'))
    widths.memory = math.max(widths.memory, #(mem_data .. ' MB'))
    widths.exit = math.max(widths.exit, #('exit: ' .. exit_str))

    table.insert(verdict_data, {
      idx = idx,
      status = status,
      time_data = time_data,
      mem_data = mem_data,
      exit_str = exit_str,
    })

    for _, line in ipairs(vim.split(tc.input, '\n')) do
      table.insert(input_lines, line)
    end
    if idx < #test_indices then
      table.insert(input_lines, '')
    end
  end

  local verdict_lines = {}
  local verdict_highlights = {}
  for _, vd in ipairs(verdict_data) do
    local test_num_part = helpers.pad_right('Test ' .. vd.idx .. ':', widths.test_num)
    local status_part = helpers.pad_right(vd.status.text, widths.status)
    local time_part = helpers.pad_right(vd.time_data, widths.time - 3) .. ' ms'
    local mem_part = helpers.pad_right(vd.mem_data, widths.memory - 3) .. ' MB'
    local exit_part = helpers.pad_right('exit: ' .. vd.exit_str, widths.exit)

    local verdict_line = test_num_part
      .. ' '
      .. status_part
      .. ' | '
      .. time_part
      .. ' | '
      .. mem_part
      .. ' | '
      .. exit_part
    table.insert(verdict_lines, verdict_line)

    local status_pos = verdict_line:find(vd.status.text, 1, true)
    if status_pos then
      table.insert(verdict_highlights, {
        status = vd.status,
        verdict_line = verdict_line,
      })
    end
  end

  if #output_lines > 0 and #verdict_lines > 0 then
    table.insert(output_lines, '')
  end

  local verdict_start = #output_lines
  for _, line in ipairs(verdict_lines) do
    table.insert(output_lines, line)
  end

  local final_highlights = {}
  for i, vh in ipairs(verdict_highlights) do
    local status_pos = vh.verdict_line:find(vh.status.text, 1, true)
    if status_pos then
      table.insert(final_highlights, {
        line = verdict_start + i - 1,
        col_start = status_pos - 1,
        col_end = status_pos - 1 + #vh.status.text,
        highlight_group = vh.status.highlight_group,
      })
    end
  end

  utils.update_buffer_content(io_state.input_buf, input_lines, nil, nil)

  local output_ns = vim.api.nvim_create_namespace('cp_io_view_output')
  utils.update_buffer_content(io_state.output_buf, output_lines, final_highlights, output_ns)
end

---@param panel_opts? PanelOpts
function M.toggle_panel(panel_opts)
  if state.get_active_panel() == 'run' then
    if current_diff_layout then
      current_diff_layout.cleanup()
      current_diff_layout = nil
      current_mode = nil
    end
    local saved = state.get_saved_session()
    if saved then
      vim.cmd(('source %s'):format(saved))
      vim.fn.delete(saved)
      state.set_saved_session(nil)
    end
    state.set_active_panel(nil)
    M.ensure_io_view()
    return
  end

  if state.get_active_panel() then
    logger.log('another panel is already active', vim.log.levels.ERROR)
    return
  end

  local platform, contest_id = state.get_platform(), state.get_contest_id()

  if not platform or not contest_id then
    logger.log(
      'No platform/contest configured. Use :CP <platform> <contest> [...] first.',
      vim.log.levels.ERROR
    )
    return
  end

  cache.load()
  local contest_data = cache.get_contest_data(platform, contest_id)
  if
    contest_data
    and contest_data.problems[contest_data.index_map[state.get_problem_id()]].interactive
  then
    logger.log('This is an interactive problem. Use :CP interact instead.', vim.log.levels.WARN)
    return
  end

  local config = config_module.get_config()
  local run = require('cp.runner.run')
  local run_render = require('cp.runner.run_render')
  local input_file = state.get_input_file()
  logger.log(('run panel: checking test cases for %s'):format(input_file or 'none'))

  if not run.load_test_cases() then
    logger.log('no test cases found', vim.log.levels.WARN)
    return
  end

  local io_state = state.get_io_view_state()
  if io_state then
    if vim.api.nvim_win_is_valid(io_state.output_win) then
      vim.api.nvim_win_close(io_state.output_win, true)
    end
    if vim.api.nvim_win_is_valid(io_state.input_win) then
      vim.api.nvim_win_close(io_state.input_win, true)
    end
    state.set_io_view_state(nil)
  end

  local session_file = vim.fn.tempname()
  state.set_saved_session(session_file)
  vim.cmd(('mksession! %s'):format(session_file))
  vim.cmd('silent only')

  local tab_buf = utils.create_buffer_with_options()
  helpers.clearcol(tab_buf)
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

  local function refresh_panel()
    if not test_buffers.tab_buf or not vim.api.nvim_buf_is_valid(test_buffers.tab_buf) then
      return
    end
    run_render.setup_highlights()
    local test_state = run.get_panel_state()
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
    local test_state = run.get_panel_state()
    if vim.tbl_isempty(test_state.test_cases) then
      return
    end
    test_state.current_index = (test_state.current_index + delta - 1) % #test_state.test_cases + 1
    refresh_panel()
  end

  setup_keybindings_for_buffer = function(buf)
    vim.keymap.set('n', 'q', function()
      M.toggle_panel()
    end, { buffer = buf, silent = true })
    vim.keymap.set('n', 't', function()
      local modes = { 'none', 'git', 'vim' }
      local current_idx = 1
      for i, mode in ipairs(modes) do
        if config.ui.panel.diff_mode == mode then
          current_idx = i
          break
        end
      end
      config.ui.panel.diff_mode = modes[(current_idx % #modes) + 1]
      refresh_panel()
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
  if panel_opts and panel_opts.debug and config.hooks and config.hooks.before_debug then
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

  refresh_panel()

  vim.schedule(function()
    if config.ui.ansi then
      require('cp.ui.ansi').setup_highlight_groups()
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
