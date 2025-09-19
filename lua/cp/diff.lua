---@class DiffResult
---@field content string[]
---@field highlights table[]?

---@class DiffBackend
---@field name string
---@field render fun(expected: string, actual: string, mode: string?): DiffResult

local M = {}

---Vim's built-in diff backend using diffthis
---@type DiffBackend
local vim_backend = {
  name = 'vim',
  render = function(expected, actual, mode)
    -- For vim backend, we return the content as-is since diffthis handles highlighting
    local expected_lines = vim.split(expected, '\n', { plain = true, trimempty = true })
    local actual_lines = vim.split(actual, '\n', { plain = true, trimempty = true })

    return {
      content = actual_lines,
      highlights = nil -- diffthis handles highlighting
    }
  end
}

---Git word-diff backend for character-level precision
---@type DiffBackend
local git_backend = {
  name = 'git',
  render = function(expected, actual, mode)
    -- Create temporary files for git diff
    local tmp_expected = vim.fn.tempname()
    local tmp_actual = vim.fn.tempname()

    vim.fn.writefile(vim.split(expected, '\n', { plain = true }), tmp_expected)
    vim.fn.writefile(vim.split(actual, '\n', { plain = true }), tmp_actual)

    local cmd = {
      'git', 'diff', '--no-index', '--word-diff=plain', '--word-diff-regex=.',
      '--no-prefix', tmp_expected, tmp_actual
    }

    local result = vim.system(cmd, { text = true }):wait()

    -- Clean up temp files
    vim.fn.delete(tmp_expected)
    vim.fn.delete(tmp_actual)

    if result.code == 0 then
      -- No differences, return actual content as-is
      return {
        content = vim.split(actual, '\n', { plain = true, trimempty = true }),
        highlights = {}
      }
    else
      -- Parse git diff output
      local lines = vim.split(result.stdout or '', '\n', { plain = true })
      local content_lines = {}
      local highlights = {}

      -- Skip git diff header lines (start with @@, +++, ---, etc.)
      local content_started = false
      for _, line in ipairs(lines) do
        if content_started or (not line:match('^@@') and not line:match('^%+%+%+') and not line:match('^%-%-%-') and not line:match('^index')) then
          content_started = true
          if line:match('^[^%-+]') or line:match('^%+') then
            -- Skip lines starting with - (removed lines) for the actual pane
            -- Only show lines that are unchanged or added
            if not line:match('^%-') then
              local clean_line = line:gsub('^%+', '') -- Remove + prefix
              table.insert(content_lines, clean_line)

              -- Parse highlights will be handled in highlight.lua
              table.insert(highlights, {
                line = #content_lines,
                content = clean_line
              })
            end
          end
        end
      end

      return {
        content = content_lines,
        highlights = highlights
      }
    end
  end
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
  local result = vim.system({'git', '--version'}, { text = true }):wait()
  return result.code == 0
end

---Get the best available backend based on config and system availability
---@param preferred_backend? string
---@return DiffBackend
function M.get_best_backend(preferred_backend)
  if preferred_backend and backends[preferred_backend] then
    if preferred_backend == 'git' and not M.is_git_available() then
      -- Fall back to vim if git is not available
      return backends.vim
    end
    return backends[preferred_backend]
  end

  -- Default to git if available, otherwise vim
  if M.is_git_available() then
    return backends.git
  else
    return backends.vim
  end
end

---Render diff using specified backend
---@param expected string
---@param actual string
---@param backend_name? string
---@param mode? string
---@return DiffResult
function M.render_diff(expected, actual, backend_name, mode)
  local backend = M.get_best_backend(backend_name)
  return backend.render(expected, actual, mode)
end

return M