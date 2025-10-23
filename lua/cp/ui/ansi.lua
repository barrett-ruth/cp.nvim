---@class AnsiParseResult
---@field lines string[]
---@field highlights Highlight[]

---@class Highlight
---@field line number
---@field col_start number
---@field col_end number
---@field highlight_group string

local M = {}

local dyn_hl_cache = {}

local ANSI_TERMINAL_COLOR_CODE_FALLBACK = {
  [0] = '#000000',
  [1] = '#800000',
  [2] = '#008000',
  [3] = '#808000',
  [4] = '#000080',
  [5] = '#800080',
  [6] = '#008080',
  [7] = '#c0c0c0',
  [8] = '#808080',
  [9] = '#ff0000',
  [10] = '#00ff00',
  [11] = '#ffff00',
  [12] = '#0000ff',
  [13] = '#ff00ff',
  [14] = '#00ffff',
  [15] = '#ffffff',
}

local function xterm_to_hex(n)
  if n >= 0 and n <= 15 then
    local key = 'terminal_color_' .. n
    return vim.g[key] or ANSI_TERMINAL_COLOR_CODE_FALLBACK[n]
  end
  if n >= 16 and n <= 231 then
    local c = n - 16
    local r = math.floor(c / 36) % 6
    local g = math.floor(c / 6) % 6
    local b = c % 6
    local function level(x)
      return x == 0 and 0 or 55 + 40 * x
    end
    return ('#%02x%02x%02x'):format(level(r), level(g), level(b))
  end
  local l = 8 + 10 * (n - 232)
  return ('#%02x%02x%02x'):format(l, l, l)
end

---@param s string|table
---@return string
function M.bytes_to_string(s)
  if type(s) == 'string' then
    return s
  end
  return table.concat(vim.tbl_map(string.char, s))
end

---@param fg table|nil
---@param bold boolean
---@param italic boolean
---@return string|nil
local function ensure_hl_for(fg, bold, italic)
  if not fg and not bold and not italic then
    return nil
  end

  local base = 'CpAnsi'
  local suffix
  local opts = {}

  if fg and fg.kind == 'named' then
    suffix = fg.name
  elseif fg and fg.kind == 'xterm' then
    suffix = ('X%03d'):format(fg.idx)

    opts.fg = xterm_to_hex(fg.idx) or 'NONE'
  elseif fg and fg.kind == 'rgb' then
    suffix = ('Rgb%02x%02x%02x'):format(fg.r, fg.g, fg.b)
    opts.fg = ('#%02x%02x%02x'):format(fg.r, fg.g, fg.b)
  end

  local parts = { base }
  if bold then
    table.insert(parts, 'Bold')
  end
  if italic then
    table.insert(parts, 'Italic')
  end
  if suffix then
    table.insert(parts, suffix)
  end
  local name = table.concat(parts)

  if not dyn_hl_cache[name] then
    if bold then
      opts.bold = true
    end
    if italic then
      opts.italic = true
    end
    vim.api.nvim_set_hl(0, name, opts)
    dyn_hl_cache[name] = true
  end
  return name
end

---@param text string
---@return AnsiParseResult
function M.parse_ansi_text(text)
  local clean_text = text:gsub('\027%[[%d;]*[a-zA-Z]', '')
  local lines = vim.split(clean_text, '\n', { plain = true })

  local highlights = {}
  local line_num = 0
  local col_pos = 0

  local ansi_state = {
    bold = false,
    italic = false,
    foreground = nil,
  }

  local function get_highlight_group()
    return ensure_hl_for(ansi_state.foreground, ansi_state.bold, ansi_state.italic)
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
---@return nil
function M.update_ansi_state(ansi_state, code_string)
  if code_string == '' or code_string == '0' then
    ansi_state.bold = false
    ansi_state.italic = false
    ansi_state.foreground = nil
    return
  end

  local codes = vim.split(code_string, ';', { plain = true })
  local idx = 1
  while idx <= #codes do
    local num = tonumber(codes[idx])

    if num == 1 then
      ansi_state.bold = true
    elseif num == 3 then
      ansi_state.italic = true
    elseif num == 22 then
      ansi_state.bold = false
    elseif num == 23 then
      ansi_state.italic = false
    elseif num and num >= 30 and num <= 37 then
      local colors = { 'Black', 'Red', 'Green', 'Yellow', 'Blue', 'Magenta', 'Cyan', 'White' }
      ansi_state.foreground = { kind = 'named', name = colors[num - 29] }
    elseif num and num >= 90 and num <= 97 then
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
      ansi_state.foreground = { kind = 'named', name = colors[num - 89] }
    elseif num == 39 then
      ansi_state.foreground = nil
    elseif num == 38 or num == 48 then
      local is_fg = (num == 38)
      local mode = tonumber(codes[idx + 1] or '')
      if mode == 5 and codes[idx + 2] then
        local pal = tonumber(codes[idx + 2]) or 0
        if is_fg then
          ansi_state.foreground = { kind = 'xterm', idx = pal }
        end
        idx = idx + 2
      elseif mode == 2 and codes[idx + 2] and codes[idx + 3] and codes[idx + 4] then
        local r = tonumber(codes[idx + 2]) or 0
        local g = tonumber(codes[idx + 3]) or 0
        local b = tonumber(codes[idx + 4]) or 0
        if is_fg then
          ansi_state.foreground = { kind = 'rgb', r = r, g = g, b = b }
        end
        idx = idx + 4
      end
    end

    idx = idx + 1
  end
end

---@return nil
function M.setup_highlight_groups()
  local color_map = {
    Black = vim.g.terminal_color_0 or ANSI_TERMINAL_COLOR_CODE_FALLBACK[0],
    Red = vim.g.terminal_color_1 or ANSI_TERMINAL_COLOR_CODE_FALLBACK[1],
    Green = vim.g.terminal_color_2 or ANSI_TERMINAL_COLOR_CODE_FALLBACK[2],
    Yellow = vim.g.terminal_color_3 or ANSI_TERMINAL_COLOR_CODE_FALLBACK[3],
    Blue = vim.g.terminal_color_4 or ANSI_TERMINAL_COLOR_CODE_FALLBACK[4],
    Magenta = vim.g.terminal_color_5 or ANSI_TERMINAL_COLOR_CODE_FALLBACK[5],
    Cyan = vim.g.terminal_color_6 or ANSI_TERMINAL_COLOR_CODE_FALLBACK[6],
    White = vim.g.terminal_color_7 or ANSI_TERMINAL_COLOR_CODE_FALLBACK[7],
    BrightBlack = vim.g.terminal_color_8 or ANSI_TERMINAL_COLOR_CODE_FALLBACK[8],
    BrightRed = vim.g.terminal_color_9 or ANSI_TERMINAL_COLOR_CODE_FALLBACK[9],
    BrightGreen = vim.g.terminal_color_10 or ANSI_TERMINAL_COLOR_CODE_FALLBACK[10],
    BrightYellow = vim.g.terminal_color_11 or ANSI_TERMINAL_COLOR_CODE_FALLBACK[11],
    BrightBlue = vim.g.terminal_color_12 or ANSI_TERMINAL_COLOR_CODE_FALLBACK[12],
    BrightMagenta = vim.g.terminal_color_13 or ANSI_TERMINAL_COLOR_CODE_FALLBACK[13],
    BrightCyan = vim.g.terminal_color_14 or ANSI_TERMINAL_COLOR_CODE_FALLBACK[14],
    BrightWhite = vim.g.terminal_color_15 or ANSI_TERMINAL_COLOR_CODE_FALLBACK[15],
  }

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

  for _, combo in ipairs(combinations) do
    for color_name, _ in pairs(color_map) do
      local parts = { 'CpAnsi' }
      if combo.bold then
        table.insert(parts, 'Bold')
      end
      if combo.italic then
        table.insert(parts, 'Italic')
      end
      table.insert(parts, color_name)
      local hl_name = table.concat(parts)
      dyn_hl_cache[hl_name] = true
    end
  end

  dyn_hl_cache['CpAnsiBold'] = true
  dyn_hl_cache['CpAnsiItalic'] = true
  dyn_hl_cache['CpAnsiBoldItalic'] = true
end

---@param text string
---@return string[]
function M.debug_ansi_tokens(text)
  local out = {}
  local i = 1
  while true do
    local s, e, codes, cmd = text:find('\027%[([%d;]*)([a-zA-Z])', i)
    if not s then
      break
    end
    table.insert(out, ('ESC[%s%s'):format(codes, cmd))
    i = e + 1
  end
  return out
end

---@param s string
---@return string
function M.hex_dump(s)
  local t = {}
  for i = 1, #s do
    t[#t + 1] = ('%02X'):format(s:byte(i))
  end
  return table.concat(t, ' ')
end

return M
