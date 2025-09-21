local M = {}

local logger = require('cp.log')

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
    logger.log('setting up Python environment for scrapers...')
    local result = vim.system({ 'uv', 'sync' }, { cwd = plugin_path, text = true }):wait()
    if result.code ~= 0 then
      logger.log('failed to setup Python environment: ' .. result.stderr, vim.log.levels.ERROR)
      return false
    end
    logger.log('python environment setup complete')
  end

  python_env_setup = true
  return true
end

return M
