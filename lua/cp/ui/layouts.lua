local M = {}

local utils = require('cp.utils')

local function create_none_diff_layout(parent_win, expected_content, actual_content)
  local expected_buf = utils.create_buffer_with_options()
  local actual_buf = utils.create_buffer_with_options()

  vim.api.nvim_set_current_win(parent_win)
  vim.cmd.split()
  vim.cmd('resize ' .. math.floor(vim.o.lines * 0.35))
  local actual_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(actual_win, actual_buf)

  vim.cmd.vsplit()
  local expected_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(expected_win, expected_buf)

  vim.api.nvim_set_option_value('filetype', 'cptest', { buf = expected_buf })
  vim.api.nvim_set_option_value('filetype', 'cptest', { buf = actual_buf })
  vim.api.nvim_set_option_value('winbar', 'Expected', { win = expected_win })
  vim.api.nvim_set_option_value('winbar', 'Actual', { win = actual_win })

  local expected_lines = vim.split(expected_content, '\n', { plain = true, trimempty = true })
  local actual_lines = vim.split(actual_content, '\n', { plain = true })

  utils.update_buffer_content(expected_buf, expected_lines, {})
  utils.update_buffer_content(actual_buf, actual_lines, {})

  return {
    buffers = { expected_buf, actual_buf },
    windows = { expected_win, actual_win },
    cleanup = function()
      pcall(vim.api.nvim_win_close, expected_win, true)
      pcall(vim.api.nvim_win_close, actual_win, true)
      pcall(vim.api.nvim_buf_delete, expected_buf, { force = true })
      pcall(vim.api.nvim_buf_delete, actual_buf, { force = true })
    end,
  }
end

local function create_vim_diff_layout(parent_win, expected_content, actual_content)
  local expected_buf = utils.create_buffer_with_options()
  local actual_buf = utils.create_buffer_with_options()

  vim.api.nvim_set_current_win(parent_win)
  vim.cmd.split()
  vim.cmd('resize ' .. math.floor(vim.o.lines * 0.35))
  local actual_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(actual_win, actual_buf)

  vim.cmd.vsplit()
  local expected_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(expected_win, expected_buf)

  vim.api.nvim_set_option_value('filetype', 'cptest', { buf = expected_buf })
  vim.api.nvim_set_option_value('filetype', 'cptest', { buf = actual_buf })
  vim.api.nvim_set_option_value('winbar', 'Expected', { win = expected_win })
  vim.api.nvim_set_option_value('winbar', 'Actual', { win = actual_win })

  local expected_lines = vim.split(expected_content, '\n', { plain = true, trimempty = true })
  local actual_lines = vim.split(actual_content, '\n', { plain = true })

  utils.update_buffer_content(expected_buf, expected_lines, {})
  utils.update_buffer_content(actual_buf, actual_lines, {})

  vim.api.nvim_set_option_value('diff', true, { win = expected_win })
  vim.api.nvim_set_option_value('diff', true, { win = actual_win })
  vim.api.nvim_win_call(expected_win, function()
    vim.cmd.diffthis()
  end)
  vim.api.nvim_win_call(actual_win, function()
    vim.cmd.diffthis()
  end)
  vim.api.nvim_set_option_value('foldcolumn', '0', { win = expected_win })
  vim.api.nvim_set_option_value('foldcolumn', '0', { win = actual_win })

  return {
    buffers = { expected_buf, actual_buf },
    windows = { expected_win, actual_win },
    cleanup = function()
      pcall(vim.api.nvim_win_close, expected_win, true)
      pcall(vim.api.nvim_win_close, actual_win, true)
      pcall(vim.api.nvim_buf_delete, expected_buf, { force = true })
      pcall(vim.api.nvim_buf_delete, actual_buf, { force = true })
    end,
  }
end

local function create_git_diff_layout(parent_win, expected_content, actual_content)
  local diff_buf = utils.create_buffer_with_options()

  vim.api.nvim_set_current_win(parent_win)
  vim.cmd.split()
  vim.cmd('resize ' .. math.floor(vim.o.lines * 0.35))
  local diff_win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(diff_win, diff_buf)

  vim.api.nvim_set_option_value('filetype', 'cptest', { buf = diff_buf })
  vim.api.nvim_set_option_value('winbar', 'Expected vs Actual', { win = diff_win })

  local diff_backend = require('cp.ui.diff')
  local backend = diff_backend.get_best_backend('git')
  local diff_result = backend.render(expected_content, actual_content)
  local highlight = require('cp.ui.highlight')
  local diff_namespace = highlight.create_namespace()

  if diff_result.raw_diff and diff_result.raw_diff ~= '' then
    highlight.parse_and_apply_diff(diff_buf, diff_result.raw_diff, diff_namespace)
  else
    local lines = vim.split(actual_content, '\n', { plain = true })
    utils.update_buffer_content(diff_buf, lines, {})
  end

  return {
    buffers = { diff_buf },
    windows = { diff_win },
    cleanup = function()
      pcall(vim.api.nvim_win_close, diff_win, true)
      pcall(vim.api.nvim_buf_delete, diff_buf, { force = true })
    end,
  }
end

local function create_single_layout(parent_win, content)
  local buf = utils.create_buffer_with_options()
  local lines = vim.split(content, '\n', { plain = true })
  utils.update_buffer_content(buf, lines, {})

  vim.api.nvim_set_current_win(parent_win)
  vim.cmd.split()
  vim.cmd('resize ' .. math.floor(vim.o.lines * 0.35))
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, buf)
  vim.api.nvim_set_option_value('filetype', 'cptest', { buf = buf })

  return {
    buffers = { buf },
    windows = { win },
    cleanup = function()
      pcall(vim.api.nvim_win_close, win, true)
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end,
  }
end

function M.create_diff_layout(mode, parent_win, expected_content, actual_content)
  if mode == 'single' then
    return create_single_layout(parent_win, actual_content)
  elseif mode == 'none' then
    return create_none_diff_layout(parent_win, expected_content, actual_content)
  elseif mode == 'git' then
    return create_git_diff_layout(parent_win, expected_content, actual_content)
  else
    return create_vim_diff_layout(parent_win, expected_content, actual_content)
  end
end

function M.update_diff_panes(
  current_diff_layout,
  current_mode,
  main_win,
  run,
  config,
  setup_keybindings_for_buffer
)
  local test_state = run.get_run_panel_state()
  local current_test = test_state.test_cases[test_state.current_index]

  if not current_test then
    return current_diff_layout, current_mode
  end

  local expected_content = current_test.expected or ''
  local actual_content = current_test.actual or '(not run yet)'
  local actual_highlights = current_test.actual_highlights or {}
  local is_compilation_failure = current_test.error
    and current_test.error:match('Compilation failed')
  local should_show_diff = current_test.status == 'fail'
    and current_test.actual
    and not is_compilation_failure

  if not should_show_diff then
    expected_content = expected_content
    actual_content = actual_content
  end

  local desired_mode = is_compilation_failure and 'single' or config.run_panel.diff_mode
  local highlight = require('cp.ui.highlight')
  local diff_namespace = highlight.create_namespace()
  local ansi_namespace = vim.api.nvim_create_namespace('cp_ansi_highlights')

  if current_diff_layout and current_mode ~= desired_mode then
    local saved_pos = vim.api.nvim_win_get_cursor(0)
    current_diff_layout.cleanup()
    current_diff_layout = nil
    current_mode = nil

    current_diff_layout =
      M.create_diff_layout(desired_mode, main_win, expected_content, actual_content)
    current_mode = desired_mode

    for _, buf in ipairs(current_diff_layout.buffers) do
      setup_keybindings_for_buffer(buf)
    end

    pcall(vim.api.nvim_win_set_cursor, 0, saved_pos)
    return current_diff_layout, current_mode
  end

  if not current_diff_layout then
    current_diff_layout =
      M.create_diff_layout(desired_mode, main_win, expected_content, actual_content)
    current_mode = desired_mode

    for _, buf in ipairs(current_diff_layout.buffers) do
      setup_keybindings_for_buffer(buf)
    end
  else
    if desired_mode == 'single' then
      local lines = vim.split(actual_content, '\n', { plain = true })
      utils.update_buffer_content(
        current_diff_layout.buffers[1],
        lines,
        actual_highlights,
        ansi_namespace
      )
    elseif desired_mode == 'git' then
      local diff_backend = require('cp.ui.diff')
      local backend = diff_backend.get_best_backend('git')
      local diff_result = backend.render(expected_content, actual_content)

      if diff_result.raw_diff and diff_result.raw_diff ~= '' then
        highlight.parse_and_apply_diff(
          current_diff_layout.buffers[1],
          diff_result.raw_diff,
          diff_namespace
        )
      else
        local lines = vim.split(actual_content, '\n', { plain = true })
        utils.update_buffer_content(
          current_diff_layout.buffers[1],
          lines,
          actual_highlights,
          ansi_namespace
        )
      end
    elseif desired_mode == 'none' then
      local expected_lines = vim.split(expected_content, '\n', { plain = true, trimempty = true })
      local actual_lines = vim.split(actual_content, '\n', { plain = true })
      utils.update_buffer_content(current_diff_layout.buffers[1], expected_lines, {})
      utils.update_buffer_content(
        current_diff_layout.buffers[2],
        actual_lines,
        actual_highlights,
        ansi_namespace
      )
    else
      local expected_lines = vim.split(expected_content, '\n', { plain = true, trimempty = true })
      local actual_lines = vim.split(actual_content, '\n', { plain = true })
      utils.update_buffer_content(current_diff_layout.buffers[1], expected_lines, {})
      utils.update_buffer_content(
        current_diff_layout.buffers[2],
        actual_lines,
        actual_highlights,
        ansi_namespace
      )

      if should_show_diff then
        vim.api.nvim_set_option_value('diff', true, { win = current_diff_layout.windows[1] })
        vim.api.nvim_set_option_value('diff', true, { win = current_diff_layout.windows[2] })
        vim.api.nvim_win_call(current_diff_layout.windows[1], function()
          vim.cmd.diffthis()
        end)
        vim.api.nvim_win_call(current_diff_layout.windows[2], function()
          vim.cmd.diffthis()
        end)
        vim.api.nvim_set_option_value('foldcolumn', '0', { win = current_diff_layout.windows[1] })
        vim.api.nvim_set_option_value('foldcolumn', '0', { win = current_diff_layout.windows[2] })
      else
        vim.api.nvim_set_option_value('diff', false, { win = current_diff_layout.windows[1] })
        vim.api.nvim_set_option_value('diff', false, { win = current_diff_layout.windows[2] })
      end
    end
  end

  return current_diff_layout, current_mode
end

return M
