local M = {}

local logger = require('cp.log')

local uname = vim.loop.os_uname()

local _time_cached = false
local _time_path = nil
local _time_reason = nil

local function is_windows()
  return uname and uname.sysname == 'Windows_NT'
end

local function check_time_is_gnu_time(bin)
  local ok = vim.fn.executable(bin) == 1
  if not ok then
    return false
  end
  local r = vim.system({ bin, '--version' }, { text = true }):wait()
  if r and r.code == 0 and r.stdout and r.stdout:lower():find('gnu time', 1, true) then
    return true
  end
  return false
end

local function find_gnu_time()
  if _time_cached then
    return _time_path, _time_reason
  end

  if is_windows() then
    _time_cached = true
    _time_path = nil
    _time_reason = 'unsupported on Windows'
    return _time_path, _time_reason
  end

  local candidates
  if uname and uname.sysname == 'Darwin' then
    candidates = { 'gtime', '/opt/homebrew/bin/gtime', '/usr/local/bin/gtime' }
  else
    candidates = { '/usr/bin/time', 'time' }
  end

  for _, bin in ipairs(candidates) do
    if check_time_is_gnu_time(bin) then
      _time_cached = true
      _time_path = bin
      _time_reason = nil
      return _time_path, _time_reason
    end
  end

  _time_cached = true
  _time_path = nil
  _time_reason = 'GNU time not found (install `time` on Linux or `brew install coreutils` on macOS)'
  return _time_path, _time_reason
end

---@return string|nil path to GNU time binary
function M.time_path()
  local path = find_gnu_time()
  return path
end

---@return {ok:boolean, path:string|nil, reason:string|nil}
function M.time_capability()
  local path, reason = find_gnu_time()
  return { ok = path ~= nil, path = path, reason = reason }
end

---@return string
function M.get_plugin_path()
  local plugin_path = debug.getinfo(1, 'S').source:sub(2)
  return vim.fn.fnamemodify(plugin_path, ':h:h:h')
end

local python_env_setup = false

---@return boolean success
function M.setup_python_env()
  if python_env_setup then
    return true
  end

  local plugin_path = M.get_plugin_path()
  local venv_dir = plugin_path .. '/.venv'

  if vim.fn.executable('uv') == 0 then
    logger.log(
      'uv is not installed. Install it to enable problem scraping: https://docs.astral.sh/uv/',
      vim.log.levels.WARN
    )
    return false
  end

  if vim.fn.isdirectory(venv_dir) == 0 then
    logger.log('Setting up Python environment for scrapers...')
    local result = vim.system({ 'uv', 'sync' }, { cwd = plugin_path, text = true }):wait()
    if result.code ~= 0 then
      logger.log('Failed to setup Python environment: ' .. result.stderr, vim.log.levels.ERROR)
      return false
    end
    logger.log('Python environment setup complete.')
  end

  python_env_setup = true
  return true
end

--- Configure the buffer with good defaults
---@param filetype? string
function M.create_buffer_with_options(filetype)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_option_value('bufhidden', 'wipe', { buf = buf })
  vim.api.nvim_set_option_value('readonly', true, { buf = buf })
  vim.api.nvim_set_option_value('modifiable', false, { buf = buf })
  if filetype then
    vim.api.nvim_set_option_value('filetype', filetype, { buf = buf })
  end
  return buf
end

function M.update_buffer_content(bufnr, lines, highlights, namespace)
  local was_readonly = vim.api.nvim_get_option_value('readonly', { buf = bufnr })

  vim.api.nvim_set_option_value('readonly', false, { buf = bufnr })
  vim.api.nvim_set_option_value('modifiable', true, { buf = bufnr })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_set_option_value('modifiable', false, { buf = bufnr })
  vim.api.nvim_set_option_value('readonly', was_readonly, { buf = bufnr })

  if highlights and namespace then
    local highlight = require('cp.ui.highlight')
    highlight.apply_highlights(bufnr, highlights, namespace)
  end
end

function M.check_required_runtime()
  if is_windows() then
    return false, 'Windows is not supported'
  end

  if vim.fn.has('nvim-0.10.0') ~= 1 then
    return false, 'Neovim 0.10.0+ required'
  end

  local cap = M.time_capability()
  if not cap.ok then
    return false, 'GNU time not found: ' .. (cap.reason or '')
  end

  if vim.fn.executable('uv') ~= 1 then
    return false, 'uv not found (https://docs.astral.sh/uv/)'
  end

  if not M.setup_python_env() then
    return false, 'failed to set up Python virtual environment'
  end

  return true
end

return M
