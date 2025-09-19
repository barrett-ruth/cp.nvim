---@class DiffResult
---@field content string[]
---@field highlights table[]?

---@class DiffBackend
---@field name string
---@field render fun(expected: string, actual: string): DiffResult

local M = {}

---Vim's built-in diff backend using diffthis
---@type DiffBackend
local vim_backend = {
  name = 'vim',
  render = function(_, actual)
    local actual_lines = vim.split(actual, '\n', { plain = true, trimempty = true })

    return {
      content = actual_lines,
      highlights = nil, -- diffthis handles highlighting
    }
  end,
}

---Git word-diff backend for character-level precision
---@type DiffBackend
local git_backend = {
  name = 'git',
  render = function(expected, actual)
    -- Create temporary files for git diff
    local tmp_expected = vim.fn.tempname()
    local tmp_actual = vim.fn.tempname()

    vim.fn.writefile(vim.split(expected, '\n', { plain = true }), tmp_expected)
    vim.fn.writefile(vim.split(actual, '\n', { plain = true }), tmp_actual)

    local cmd = {
      'git',
      'diff',
      '--no-index',
      '--word-diff=plain',
      '--word-diff-regex=.',
      '--no-prefix',
      tmp_expected,
      tmp_actual,
    }

    local result = vim.system(cmd, { text = true }):wait()

    -- Clean up temp files
    vim.fn.delete(tmp_expected)
    vim.fn.delete(tmp_actual)

    if result.code == 0 then
      return {
        content = vim.split(actual, '\n', { plain = true, trimempty = true }),
        highlights = {},
      }
    else
      return {
        content = {},
        highlights = {},
        raw_diff = result.stdout or '',
      }
    end
  end,
}

---Available diff backends
---@type table<string, DiffBackend>
local backends = {
  vim = vim_backend,
  git = git_backend,
}

---Get available backend names
---@return string[]
function M.get_available_backends()
  return vim.tbl_keys(backends)
end

---Get a diff backend by name
---@param name string
---@return DiffBackend?
function M.get_backend(name)
  return backends[name]
end

---Check if git backend is available
---@return boolean
function M.is_git_available()
  local result = vim.system({ 'git', '--version' }, { text = true }):wait()
  return result.code == 0
end

---Get the best available backend based on config and system availability
---@param preferred_backend? string
---@return DiffBackend
function M.get_best_backend(preferred_backend)
  if preferred_backend and backends[preferred_backend] then
    if preferred_backend == 'git' and not M.is_git_available() then
      return backends.vim
    end
    return backends[preferred_backend]
  end

  return backends.vim
end

---Render diff using specified backend
---@param expected string
---@param actual string
---@param backend_name? string
---@return DiffResult
function M.render_diff(expected, actual, backend_name)
  local backend = M.get_best_backend(backend_name)
  return backend.render(expected, actual)
end

return M
