---@class DiffResult
---@field content string[]
---@field highlights table[]?
---@field raw_diff string?

---@class DiffBackend
---@field name string
---@field render fun(expected: string, actual: string): DiffResult

local M = {}

---@type DiffBackend
local vim_backend = {
  name = 'vim',
  render = function(_, actual)
    local actual_lines = vim.split(actual, '\n', { plain = true, trimempty = true })

    return {
      content = actual_lines,
      highlights = nil,
    }
  end,
}

---@type DiffBackend
local none_backend = {
  name = 'none',
  render = function(expected, actual)
    local expected_lines = vim.split(expected, '\n', { plain = true, trimempty = true })
    local actual_lines = vim.split(actual, '\n', { plain = true, trimempty = true })

    return {
      content = { expected = expected_lines, actual = actual_lines },
      highlights = {},
    }
  end,
}

---@type DiffBackend
local git_backend = {
  name = 'git',
  render = function(expected, actual)
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

    vim.fn.delete(tmp_expected)
    vim.fn.delete(tmp_actual)

    if result.code == 0 then
      return {
        content = vim.split(actual, '\n', { plain = true, trimempty = true }),
        highlights = {},
      }
    else
      local diff_content = result.stdout or ''
      local lines = {}
      local highlights = {}
      local line_num = 0

      for line in diff_content:gmatch('[^\n]*') do
        if
          line:match('^[%s%+%-]')
          or (not line:match('^[@%-+]') and not line:match('^index') and not line:match('^diff'))
        then
          local clean_line = line
          if line:match('^[%+%-]') then
            clean_line = line:sub(2)
          end

          local col_pos = 0
          local processed_line = ''
          local i = 1

          while i <= #clean_line do
            local removed_start, removed_end = clean_line:find('%[%-[^%-]*%-]', i)
            local added_start, added_end = clean_line:find('{%+[^%+]*%+}', i)

            local next_marker_start = nil
            local marker_type = nil

            if removed_start and (not added_start or removed_start < added_start) then
              next_marker_start = removed_start
              marker_type = 'removed'
            elseif added_start then
              next_marker_start = added_start
              marker_type = 'added'
            end

            if next_marker_start then
              if next_marker_start > i then
                local before_text = clean_line:sub(i, next_marker_start - 1)
                processed_line = processed_line .. before_text
                col_pos = col_pos + #before_text
              end

              local marker_end = (marker_type == 'removed') and removed_end or added_end
              local marker_text = clean_line:sub(next_marker_start, marker_end)
              local content_text

              if marker_type == 'removed' then
                content_text = marker_text:sub(3, -3)
                table.insert(highlights, {
                  line = line_num,
                  col_start = col_pos,
                  col_end = col_pos + #content_text,
                  highlight_group = 'DiffDelete',
                })
              else
                content_text = marker_text:sub(3, -3)
                table.insert(highlights, {
                  line = line_num,
                  col_start = col_pos,
                  col_end = col_pos + #content_text,
                  highlight_group = 'DiffAdd',
                })
              end

              processed_line = processed_line .. content_text
              col_pos = col_pos + #content_text
              i = marker_end + 1
            else
              local rest = clean_line:sub(i)
              processed_line = processed_line .. rest
              break
            end
          end

          table.insert(lines, processed_line)
          line_num = line_num + 1
        end
      end

      return {
        content = lines,
        highlights = highlights,
        raw_diff = diff_content,
      }
    end
  end,
}

---@type table<string, DiffBackend>
local backends = {
  none = none_backend,
  vim = vim_backend,
  git = git_backend,
}

---@return string[]
function M.get_available_backends()
  return vim.tbl_keys(backends)
end

---@param name string
---@return DiffBackend?
function M.get_backend(name)
  return backends[name]
end

---@return boolean
function M.is_git_available()
  local result = vim.system({ 'git', '--version' }, { text = true }):wait()
  return result.code == 0
end

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

---@param expected string
---@param actual string
---@param backend_name? string
---@return DiffResult
function M.render_diff(expected, actual, backend_name)
  local backend = M.get_best_backend(backend_name)
  return backend.render(expected, actual)
end

return M
