---@class DiffHighlight
---@field line number
---@field col_start number
---@field col_end number
---@field highlight_group string

---@class ParsedDiff
---@field content string[]
---@field highlights DiffHighlight[]

local M = {}

---@param text string Raw git diff output line
---@return string cleaned_text, DiffHighlight[]
local function parse_diff_line(text)
  local result_text = ''
  local highlights = {}
  local pos = 1

  while pos <= #text do
    local removed_start, removed_end, removed_content = text:find('%[%-(.-)%-%]', pos)
    if removed_start and removed_start == pos then
      local highlight_start = #result_text
      result_text = result_text .. removed_content
      table.insert(highlights, {
        line = 0,
        col_start = highlight_start,
        col_end = #result_text,
        highlight_group = 'DiffDelete',
      })
      pos = removed_end + 1
    else
      local added_start, added_end, added_content = text:find('{%+(.-)%+}', pos)
      if added_start and added_start == pos then
        local highlight_start = #result_text
        result_text = result_text .. added_content
        table.insert(highlights, {
          line = 0,
          col_start = highlight_start,
          col_end = #result_text,
          highlight_group = 'DiffAdd',
        })
        pos = added_end + 1
      else
        result_text = result_text .. text:sub(pos, pos)
        pos = pos + 1
      end
    end
  end

  return result_text, highlights
end

---@param diff_output string
---@return ParsedDiff
function M.parse_git_diff(diff_output)
  if diff_output == '' then
    return { content = {}, highlights = {} }
  end

  local lines = vim.split(diff_output, '\n', { plain = true })
  local content_lines = {}
  local all_highlights = {}

  local content_started = false
  for _, line in ipairs(lines) do
    if
      content_started
      or (
        not line:match('^@@')
        and not line:match('^%+%+%+')
        and not line:match('^%-%-%-')
        and not line:match('^index')
        and not line:match('^diff %-%-git')
      )
    then
      content_started = true

      if line:match('^%+') then
        local clean_line = line:sub(2)
        local parsed_line, line_highlights = parse_diff_line(clean_line)

        table.insert(content_lines, parsed_line)

        local line_num = #content_lines
        for _, highlight in ipairs(line_highlights) do
          highlight.line = line_num - 1
          table.insert(all_highlights, highlight)
        end
      elseif not line:match('^%-') and not line:match('^\\') then
        local clean_line = line:match('^%s') and line:sub(2) or line
        local parsed_line, line_highlights = parse_diff_line(clean_line)

        if parsed_line ~= '' then
          table.insert(content_lines, parsed_line)

          local line_num = #content_lines
          for _, highlight in ipairs(line_highlights) do
            highlight.line = line_num - 1
            table.insert(all_highlights, highlight)
          end
        end
      end
    end
  end

  return {
    content = content_lines,
    highlights = all_highlights,
  }
end

---@param bufnr number
---@param highlights DiffHighlight[]
---@param namespace number
function M.apply_highlights(bufnr, highlights, namespace)
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)

  for _, highlight in ipairs(highlights) do
    if highlight.col_start < highlight.col_end then
      vim.api.nvim_buf_set_extmark(bufnr, namespace, highlight.line, highlight.col_start, {
        end_col = highlight.col_end,
        hl_group = highlight.highlight_group,
        priority = 100,
      })
    end
  end
end

---@return number
function M.create_namespace()
  return vim.api.nvim_create_namespace('cp_diff_highlights')
end

---@param bufnr number
---@param diff_output string
---@param namespace number
---@return string[] content_lines
function M.parse_and_apply_diff(bufnr, diff_output, namespace)
  local parsed = M.parse_git_diff(diff_output)

  local was_modifiable = vim.api.nvim_get_option_value('modifiable', { buf = bufnr })
  local was_readonly = vim.api.nvim_get_option_value('readonly', { buf = bufnr })

  vim.api.nvim_set_option_value('readonly', false, { buf = bufnr })
  vim.api.nvim_set_option_value('modifiable', true, { buf = bufnr })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, parsed.content)
  vim.api.nvim_set_option_value('modifiable', was_modifiable, { buf = bufnr })
  vim.api.nvim_set_option_value('readonly', was_readonly, { buf = bufnr })

  M.apply_highlights(bufnr, parsed.highlights, namespace)

  return parsed.content
end

return M
