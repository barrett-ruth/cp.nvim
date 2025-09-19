---@class DiffHighlight
---@field line number
---@field col_start number
---@field col_end number
---@field highlight_group string

---@class ParsedDiff
---@field content string[]
---@field highlights DiffHighlight[]

local M = {}

---Parse git diff markers and extract highlight information
---@param text string Raw git diff output line
---@return string cleaned_text, DiffHighlight[]
local function parse_diff_line(text)
  local cleaned_text = text
  local offset = 0

  -- Pattern for removed text: [-removed text-]
  for removed_text in text:gmatch('%[%-(.-)%-%]') do
    local start_pos = text:find('%[%-' .. vim.pesc(removed_text) .. '%-%]', 1, false)
    if start_pos then
      cleaned_text = cleaned_text:gsub('%[%-' .. vim.pesc(removed_text) .. '%-%]', '', 1)
    end
  end

  -- Reset for added text parsing on the cleaned text
  local final_text = cleaned_text
  local final_highlights = {}
  offset = 0

  -- Pattern for added text: {+added text+}
  for added_text in cleaned_text:gmatch('{%+(.-)%+}') do
    local start_pos = final_text:find('{%+' .. vim.pesc(added_text) .. '%+}', 1, false)
    if start_pos then
      -- Calculate position after previous highlights
      local highlight_start = start_pos - offset - 1 -- 0-based for extmarks
      local highlight_end = highlight_start + #added_text

      table.insert(final_highlights, {
        line = 0, -- Will be set by caller
        col_start = highlight_start,
        col_end = highlight_end,
        highlight_group = 'CpDiffAdded',
      })

      -- Remove the marker
      final_text = final_text:gsub('{%+' .. vim.pesc(added_text) .. '%+}', added_text, 1)
      offset = offset + 4 -- Length of {+ and +}
    end
  end

  return final_text, final_highlights
end

---Parse complete git diff output
---@param diff_output string
---@return ParsedDiff
function M.parse_git_diff(diff_output)
  if diff_output == '' then
    return { content = {}, highlights = {} }
  end

  local lines = vim.split(diff_output, '\n', { plain = true })
  local content_lines = {}
  local all_highlights = {}

  -- Skip git diff header lines
  local content_started = false
  for _, line in ipairs(lines) do
    -- Skip header lines (@@, +++, ---, index, etc.)
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

      -- Process content lines
      if line:match('^%+') then
        -- Added line - remove + prefix and parse highlights
        local clean_line = line:sub(2) -- Remove + prefix
        local parsed_line, line_highlights = parse_diff_line(clean_line)

        table.insert(content_lines, parsed_line)

        -- Set line numbers for highlights
        local line_num = #content_lines
        for _, highlight in ipairs(line_highlights) do
          highlight.line = line_num - 1 -- 0-based for extmarks
          table.insert(all_highlights, highlight)
        end
      elseif not line:match('^%-') and not line:match('^\\') then -- Skip removed lines and "\ No newline" messages
        -- Unchanged line - remove leading space if present
        local clean_line = line:match('^%s') and line:sub(2) or line
        local parsed_line, line_highlights = parse_diff_line(clean_line)
        table.insert(content_lines, parsed_line)

        -- Set line numbers for any highlights (shouldn't be any for unchanged lines)
        local line_num = #content_lines
        for _, highlight in ipairs(line_highlights) do
          highlight.line = line_num - 1 -- 0-based for extmarks
          table.insert(all_highlights, highlight)
        end
      end
    end
  end

  return {
    content = content_lines,
    highlights = all_highlights,
  }
end

---Apply highlights to a buffer using extmarks
---@param bufnr number
---@param highlights DiffHighlight[]
---@param namespace number
function M.apply_highlights(bufnr, highlights, namespace)
  -- Clear existing highlights in this namespace
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

---Create namespace for diff highlights
---@return number
function M.create_namespace()
  return vim.api.nvim_create_namespace('cp_diff_highlights')
end

---Parse and apply git diff to buffer
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
