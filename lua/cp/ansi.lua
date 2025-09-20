---@class AnsiParseResult
---@field lines string[]
---@field highlights table[]

local M = {}

---@param raw_output string|table
---@return string
function M.bytes_to_string(raw_output)
  if type(raw_output) == 'string' then
    return raw_output
  end
  return table.concat(vim.tbl_map(string.char, raw_output))
end

---@param text string
---@return AnsiParseResult
function M.parse_ansi_text(text)
  local clean_text = text:gsub('\027%[[%d;]*[a-zA-Z]', '')
  local lines = vim.split(clean_text, '\n', { plain = true, trimempty = false })

  local highlights = {}
  local line_num = 0
  local col_pos = 0
  local current_style = nil

  local i = 1
  while i <= #text do
    local ansi_start, ansi_end, code, cmd = text:find('\027%[([%d;]*)([a-zA-Z])', i)

    if ansi_start then
      if ansi_start > i then
        local segment = text:sub(i, ansi_start - 1)
        if current_style then
          local start_line = line_num
          local start_col = col_pos

          for char in segment:gmatch('.') do
            if char == '\n' then
              if col_pos > start_col then
                table.insert(highlights, {
                  line = start_line,
                  col_start = start_col,
                  col_end = col_pos,
                  highlight_group = current_style,
                })
              end
              line_num = line_num + 1
              start_line = line_num
              col_pos = 0
              start_col = 0
            else
              col_pos = col_pos + 1
            end
          end

          if col_pos > start_col then
            table.insert(highlights, {
              line = start_line,
              col_start = start_col,
              col_end = col_pos,
              highlight_group = current_style,
            })
          end
        else
          for char in segment:gmatch('.') do
            if char == '\n' then
              line_num = line_num + 1
              col_pos = 0
            else
              col_pos = col_pos + 1
            end
          end
        end
      end

      if cmd == 'm' then
        local logger = require('cp.log')
        logger.log('Found color code: "' .. code .. '"')
        current_style = M.ansi_code_to_highlight(code)
        logger.log('Mapped to highlight: ' .. (current_style or 'nil'))
      end
      i = ansi_end + 1
    else
      local segment = text:sub(i)
      if current_style and segment ~= '' then
        local start_line = line_num
        local start_col = col_pos

        for char in segment:gmatch('.') do
          if char == '\n' then
            if col_pos > start_col then
              table.insert(highlights, {
                line = start_line,
                col_start = start_col,
                col_end = col_pos,
                highlight_group = current_style,
              })
            end
            line_num = line_num + 1
            start_line = line_num
            col_pos = 0
            start_col = 0
          else
            col_pos = col_pos + 1
          end
        end

        if col_pos > start_col then
          table.insert(highlights, {
            line = start_line,
            col_start = start_col,
            col_end = col_pos,
            highlight_group = current_style,
          })
        end
      end
      break
    end
  end

  return {
    lines = lines,
    highlights = highlights,
  }
end

---@param code string
---@return string?
function M.ansi_code_to_highlight(code)
  local color_map = {
    -- Simple colors
    ['31'] = 'CpAnsiRed',
    ['32'] = 'CpAnsiGreen',
    ['33'] = 'CpAnsiYellow',
    ['34'] = 'CpAnsiBlue',
    ['35'] = 'CpAnsiMagenta',
    ['36'] = 'CpAnsiCyan',
    ['37'] = 'CpAnsiWhite',
    ['91'] = 'CpAnsiBrightRed',
    ['92'] = 'CpAnsiBrightGreen',
    ['93'] = 'CpAnsiBrightYellow',
    -- Bold colors (G++ style)
    ['01;31'] = 'CpAnsiBrightRed', -- bold red
    ['01;32'] = 'CpAnsiBrightGreen', -- bold green
    ['01;33'] = 'CpAnsiBrightYellow', -- bold yellow
    ['01;34'] = 'CpAnsiBrightBlue', -- bold blue
    ['01;35'] = 'CpAnsiBrightMagenta', -- bold magenta
    ['01;36'] = 'CpAnsiBrightCyan', -- bold cyan
    -- Bold/formatting only
    ['01'] = 'CpAnsiBold', -- bold text
    ['1'] = 'CpAnsiBold', -- bold text (alternate)
    -- Reset codes
    ['0'] = nil,
    [''] = nil,
  }
  return color_map[code]
end

function M.setup_highlight_groups()
  local groups = {
    CpAnsiRed = { fg = vim.g.terminal_color_1 },
    CpAnsiGreen = { fg = vim.g.terminal_color_2 },
    CpAnsiYellow = { fg = vim.g.terminal_color_3 },
    CpAnsiBlue = { fg = vim.g.terminal_color_4 },
    CpAnsiMagenta = { fg = vim.g.terminal_color_5 },
    CpAnsiCyan = { fg = vim.g.terminal_color_6 },
    CpAnsiWhite = { fg = vim.g.terminal_color_7 },
    CpAnsiBrightRed = { fg = vim.g.terminal_color_9 },
    CpAnsiBrightGreen = { fg = vim.g.terminal_color_10 },
    CpAnsiBrightYellow = { fg = vim.g.terminal_color_11 },
    CpAnsiBrightBlue = { fg = vim.g.terminal_color_12 },
    CpAnsiBrightMagenta = { fg = vim.g.terminal_color_13 },
    CpAnsiBrightCyan = { fg = vim.g.terminal_color_14 },
    CpAnsiBold = { bold = true },
  }

  for name, opts in pairs(groups) do
    vim.api.nvim_set_hl(0, name, opts)
  end
end

return M
