---@class AnsiParseResult
---@field lines string[]
---@field highlights any[]

local M = {}

local logger = require('cp.log')

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

  local ansi_state = {
    bold = false,
    italic = false,
    foreground = nil,
  }

  local function get_highlight_group()
    if not ansi_state.bold and not ansi_state.italic and not ansi_state.foreground then
      return nil
    end

    local parts = { 'CpAnsi' }
    if ansi_state.bold then
      table.insert(parts, 'Bold')
    end
    if ansi_state.italic then
      table.insert(parts, 'Italic')
    end
    if ansi_state.foreground then
      table.insert(parts, ansi_state.foreground)
    end

    return table.concat(parts)
  end

  local function apply_highlight(start_line, start_col, end_col)
    local hl_group = get_highlight_group()
    if hl_group then
      table.insert(highlights, {
        line = start_line,
        col_start = start_col,
        col_end = end_col,
        highlight_group = hl_group,
      })
    end
  end

  local i = 1
  while i <= #text do
    local ansi_start, ansi_end, code, cmd = text:find('\027%[([%d;]*)([a-zA-Z])', i)

    if ansi_start then
      if ansi_start > i then
        local segment = text:sub(i, ansi_start - 1)
        local start_line = line_num
        local start_col = col_pos

        for char in segment:gmatch('.') do
          if char == '\n' then
            if col_pos > start_col then
              apply_highlight(start_line, start_col, col_pos)
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
          apply_highlight(start_line, start_col, col_pos)
        end
      end

      if cmd == 'm' then
        M.update_ansi_state(ansi_state, code)
      end
      i = ansi_end + 1
    else
      local segment = text:sub(i)
      if segment ~= '' then
        local start_line = line_num
        local start_col = col_pos

        for char in segment:gmatch('.') do
          if char == '\n' then
            if col_pos > start_col then
              apply_highlight(start_line, start_col, col_pos)
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
          apply_highlight(start_line, start_col, col_pos)
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

---@param ansi_state table
---@param code_string string
function M.update_ansi_state(ansi_state, code_string)
  if code_string == '' or code_string == '0' then
    ansi_state.bold = false
    ansi_state.italic = false
    ansi_state.foreground = nil
    return
  end

  local codes = vim.split(code_string, ';', { plain = true })

  for _, code in ipairs(codes) do
    local num = tonumber(code)
    if num then
      if num == 1 then
        ansi_state.bold = true
      elseif num == 3 then
        ansi_state.italic = true
      elseif num == 22 then
        ansi_state.bold = false
      elseif num == 23 then
        ansi_state.italic = false
      elseif num >= 30 and num <= 37 then
        local colors = { 'Black', 'Red', 'Green', 'Yellow', 'Blue', 'Magenta', 'Cyan', 'White' }
        ansi_state.foreground = colors[num - 29]
      elseif num >= 90 and num <= 97 then
        local colors = {
          'BrightBlack',
          'BrightRed',
          'BrightGreen',
          'BrightYellow',
          'BrightBlue',
          'BrightMagenta',
          'BrightCyan',
          'BrightWhite',
        }
        ansi_state.foreground = colors[num - 89]
      elseif num == 39 then
        ansi_state.foreground = nil
      end
    end
  end
end

function M.setup_highlight_groups()
  local color_map = {
    Black = vim.g.terminal_color_0,
    Red = vim.g.terminal_color_1,
    Green = vim.g.terminal_color_2,
    Yellow = vim.g.terminal_color_3,
    Blue = vim.g.terminal_color_4,
    Magenta = vim.g.terminal_color_5,
    Cyan = vim.g.terminal_color_6,
    White = vim.g.terminal_color_7,
    BrightBlack = vim.g.terminal_color_8,
    BrightRed = vim.g.terminal_color_9,
    BrightGreen = vim.g.terminal_color_10,
    BrightYellow = vim.g.terminal_color_11,
    BrightBlue = vim.g.terminal_color_12,
    BrightMagenta = vim.g.terminal_color_13,
    BrightCyan = vim.g.terminal_color_14,
    BrightWhite = vim.g.terminal_color_15,
  }

  if vim.tbl_count(color_map) < 16 then
    logger.log(
      'ansi terminal colors (vim.g.terminal_color_*) not configured. ANSI colors will not display properly. ',
      vim.log.levels.WARN
    )
  end

  local combinations = {
    { bold = false, italic = false },
    { bold = true, italic = false },
    { bold = false, italic = true },
    { bold = true, italic = true },
  }

  for _, combo in ipairs(combinations) do
    for color_name, terminal_color in pairs(color_map) do
      local parts = { 'CpAnsi' }
      local opts = { fg = terminal_color or 'NONE' }

      if combo.bold then
        table.insert(parts, 'Bold')
        opts.bold = true
      end
      if combo.italic then
        table.insert(parts, 'Italic')
        opts.italic = true
      end
      table.insert(parts, color_name)

      local hl_name = table.concat(parts)
      vim.api.nvim_set_hl(0, hl_name, opts)
    end
  end

  vim.api.nvim_set_hl(0, 'CpAnsiBold', { bold = true })
  vim.api.nvim_set_hl(0, 'CpAnsiItalic', { italic = true })
  vim.api.nvim_set_hl(0, 'CpAnsiBoldItalic', { bold = true, italic = true })
end

return M
