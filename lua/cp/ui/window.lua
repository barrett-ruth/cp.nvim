---@class WindowState
---@field windows table<integer, WindowData>
---@field current_win integer
---@field layout string

---@class WindowData
---@field bufnr integer
---@field view table
---@field width integer
---@field height integer

local M = {}
local constants = require('cp.constants')

---@return WindowState
function M.save_layout()
  local windows = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local bufnr = vim.api.nvim_win_get_buf(win)
      windows[win] = {
        bufnr = bufnr,
        view = vim.fn.winsaveview(),
        width = vim.api.nvim_win_get_width(win),
        height = vim.api.nvim_win_get_height(win),
      }
    end
  end

  return {
    windows = windows,
    current_win = vim.api.nvim_get_current_win(),
    layout = vim.fn.winrestcmd(),
  }
end

---@param state? WindowState
---@param tile_fn? fun(source_buf: integer, input_buf: integer, output_buf: integer)
function M.restore_layout(state, tile_fn)
  vim.validate({
    state = { state, { 'table', 'nil' }, true },
    tile_fn = { tile_fn, { 'function', 'nil' }, true },
  })

  if not state then
    return
  end

  vim.cmd.diffoff()

  local problem_id = vim.fn.expand('%:t:r')
  if problem_id == '' then
    for win, win_state in pairs(state.windows) do
      if vim.api.nvim_win_is_valid(win) and vim.api.nvim_buf_is_valid(win_state.bufnr) then
        local bufname = vim.api.nvim_buf_get_name(win_state.bufnr)
        if
          not bufname:match('%.in$')
          and not bufname:match('%.out$')
          and not bufname:match('%.expected$')
        then
          problem_id = vim.fn.fnamemodify(bufname, ':t:r')
          break
        end
      end
    end
  end

  if problem_id ~= '' then
    vim.cmd('silent only')

    local base_fp = vim.fn.getcwd()
    local input_file = ('%s/io/%s.in'):format(base_fp, problem_id)
    local output_file = ('%s/io/%s.out'):format(base_fp, problem_id)
    local source_files = vim.fn.glob(problem_id .. '.*')
    local source_file
    if source_files ~= '' then
      local files = vim.split(source_files, '\n')
      local known_extensions = vim.tbl_keys(constants.filetype_to_language)
      for _, file in ipairs(files) do
        local ext = vim.fn.fnamemodify(file, ':e')
        if vim.tbl_contains(known_extensions, ext) then
          source_file = file
          break
        end
      end
      source_file = source_file or files[1]
    end

    if not source_file or vim.fn.filereadable(source_file) == 0 then
      return
    end

    vim.cmd.edit(source_file)
    local source_buf = vim.api.nvim_get_current_buf()
    local input_buf = vim.fn.bufnr(input_file, true)
    local output_buf = vim.fn.bufnr(output_file, true)

    if tile_fn then
      tile_fn(source_buf, input_buf, output_buf)
    else
      M.default_tile(source_buf, input_buf, output_buf)
    end
  else
    vim.cmd(state.layout)

    for win, win_state in pairs(state.windows) do
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_set_current_win(win)
        if vim.api.nvim_get_current_buf() == win_state.bufnr then
          vim.fn.winrestview(win_state.view)
        end
      end
    end

    if vim.api.nvim_win_is_valid(state.current_win) then
      vim.api.nvim_set_current_win(state.current_win)
    end
  end
end

---@param source_buf integer
---@param input_buf integer
---@param output_buf integer
local function default_tile(source_buf, input_buf, output_buf)
  vim.validate({
    source_buf = { source_buf, 'number' },
    input_buf = { input_buf, 'number' },
    output_buf = { output_buf, 'number' },
  })

  vim.api.nvim_set_current_buf(source_buf)
  vim.cmd.vsplit()
  vim.api.nvim_set_current_buf(output_buf)
  vim.bo.filetype = 'cp'
  vim.cmd(('vertical resize %d'):format(math.floor(vim.o.columns * 0.3)))
  vim.cmd.split()
  vim.api.nvim_set_current_buf(input_buf)
  vim.bo.filetype = 'cp'
  vim.cmd.wincmd('h')
end

M.default_tile = default_tile

return M
