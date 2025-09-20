describe('ansi parser', function()
  local ansi = require('cp.ansi')

  describe('bytes_to_string', function()
    it('returns string as-is', function()
      local input = 'hello world'
      assert.equals('hello world', ansi.bytes_to_string(input))
    end)

    it('converts byte array to string', function()
      local input = { 104, 101, 108, 108, 111 }
      assert.equals('hello', ansi.bytes_to_string(input))
    end)
  end)

  describe('parse_ansi_text', function()
    it('strips ansi codes from simple text', function()
      local input = 'Hello \027[31mworld\027[0m!'
      local result = ansi.parse_ansi_text(input)

      assert.equals('Hello world!', table.concat(result.lines, '\n'))
    end)

    it('handles text without ansi codes', function()
      local input = 'Plain text'
      local result = ansi.parse_ansi_text(input)

      assert.equals('Plain text', table.concat(result.lines, '\n'))
      assert.equals(0, #result.highlights)
    end)

    it('creates correct highlight for simple colored text', function()
      local input = 'Hello \027[31mworld\027[0m!'
      local result = ansi.parse_ansi_text(input)

      assert.equals(1, #result.highlights)
      local highlight = result.highlights[1]
      assert.equals(0, highlight.line)
      assert.equals(6, highlight.col_start)
      assert.equals(11, highlight.col_end)
      assert.equals('CpAnsiRed', highlight.highlight_group)
    end)

    it('handles bold text', function()
      local input = 'Hello \027[1mbold\027[0m world'
      local result = ansi.parse_ansi_text(input)

      assert.equals('Hello bold world', table.concat(result.lines, '\n'))
      assert.equals(1, #result.highlights)
      local highlight = result.highlights[1]
      assert.equals('CpAnsiBold', highlight.highlight_group)
    end)

    it('handles italic text', function()
      local input = 'Hello \027[3mitalic\027[0m world'
      local result = ansi.parse_ansi_text(input)

      assert.equals('Hello italic world', table.concat(result.lines, '\n'))
      assert.equals(1, #result.highlights)
      local highlight = result.highlights[1]
      assert.equals('CpAnsiItalic', highlight.highlight_group)
    end)

    it('handles bold + color combination', function()
      local input = 'Hello \027[1;31mbold red\027[0m world'
      local result = ansi.parse_ansi_text(input)

      assert.equals('Hello bold red world', table.concat(result.lines, '\n'))
      assert.equals(1, #result.highlights)
      local highlight = result.highlights[1]
      assert.equals('CpAnsiBoldRed', highlight.highlight_group)
      assert.equals(6, highlight.col_start)
      assert.equals(14, highlight.col_end)
    end)

    it('handles italic + color combination', function()
      local input = 'Hello \027[3;32mitalic green\027[0m world'
      local result = ansi.parse_ansi_text(input)

      assert.equals('Hello italic green world', table.concat(result.lines, '\n'))
      assert.equals(1, #result.highlights)
      local highlight = result.highlights[1]
      assert.equals('CpAnsiItalicGreen', highlight.highlight_group)
    end)

    it('handles bold + italic + color combination', function()
      local input = 'Hello \027[1;3;33mbold italic yellow\027[0m world'
      local result = ansi.parse_ansi_text(input)

      assert.equals('Hello bold italic yellow world', table.concat(result.lines, '\n'))
      assert.equals(1, #result.highlights)
      local highlight = result.highlights[1]
      assert.equals('CpAnsiBoldItalicYellow', highlight.highlight_group)
    end)

    it('handles sequential attribute setting', function()
      local input = 'Hello \027[1m\027[31mbold red\027[0m world'
      local result = ansi.parse_ansi_text(input)

      assert.equals('Hello bold red world', table.concat(result.lines, '\n'))
      assert.equals(1, #result.highlights)
      local highlight = result.highlights[1]
      assert.equals('CpAnsiBoldRed', highlight.highlight_group)
    end)

    it('handles selective attribute reset', function()
      local input = 'Hello \027[1;31mbold red\027[22mno longer bold\027[0m world'
      local result = ansi.parse_ansi_text(input)

      assert.equals('Hello bold redno longer bold world', table.concat(result.lines, '\n'))
      assert.equals(2, #result.highlights)

      local bold_red = result.highlights[1]
      assert.equals('CpAnsiBoldRed', bold_red.highlight_group)
      assert.equals(6, bold_red.col_start)
      assert.equals(14, bold_red.col_end)

      local just_red = result.highlights[2]
      assert.equals('CpAnsiRed', just_red.highlight_group)
      assert.equals(14, just_red.col_start)
      assert.equals(28, just_red.col_end)
    end)

    it('handles bright colors', function()
      local input = 'Hello \027[91mbright red\027[0m world'
      local result = ansi.parse_ansi_text(input)

      assert.equals(1, #result.highlights)
      local highlight = result.highlights[1]
      assert.equals('CpAnsiBrightRed', highlight.highlight_group)
    end)

    it('handles compiler-like output with complex formatting', function()
      local input =
        "error.cpp:10:5: \027[1m\027[31merror:\027[0m\027[1m 'undefined' was not declared\027[0m"
      local result = ansi.parse_ansi_text(input)

      local clean_text = table.concat(result.lines, '\n')
      assert.equals("error.cpp:10:5: error: 'undefined' was not declared", clean_text)
      assert.equals(2, #result.highlights)

      local error_highlight = result.highlights[1]
      assert.equals('CpAnsiBoldRed', error_highlight.highlight_group)
      assert.equals(16, error_highlight.col_start)
      assert.equals(22, error_highlight.col_end)

      local message_highlight = result.highlights[2]
      assert.equals('CpAnsiBold', message_highlight.highlight_group)
      assert.equals(22, message_highlight.col_start)
      assert.equals(51, message_highlight.col_end)
    end)

    it('handles multiline with persistent state', function()
      local input = '\027[1;31mline1\nline2\nline3\027[0m'
      local result = ansi.parse_ansi_text(input)

      assert.equals('line1\nline2\nline3', table.concat(result.lines, '\n'))
      assert.equals(3, #result.highlights)

      for i, highlight in ipairs(result.highlights) do
        assert.equals('CpAnsiBoldRed', highlight.highlight_group)
        assert.equals(i - 1, highlight.line)
        assert.equals(0, highlight.col_start)
        assert.equals(5, highlight.col_end)
      end
    end)
  end)

  describe('update_ansi_state', function()
    it('resets all state on reset code', function()
      local state = { bold = true, italic = true, foreground = 'Red' }
      ansi.update_ansi_state(state, '0')

      assert.is_false(state.bold)
      assert.is_false(state.italic)
      assert.is_nil(state.foreground)
    end)

    it('sets individual attributes', function()
      local state = { bold = false, italic = false, foreground = nil }

      ansi.update_ansi_state(state, '1')
      assert.is_true(state.bold)

      ansi.update_ansi_state(state, '3')
      assert.is_true(state.italic)

      ansi.update_ansi_state(state, '31')
      assert.equals('Red', state.foreground)
    end)

    it('handles compound codes', function()
      local state = { bold = false, italic = false, foreground = nil }
      ansi.update_ansi_state(state, '1;3;31')

      assert.is_true(state.bold)
      assert.is_true(state.italic)
      assert.equals('Red', state.foreground)
    end)

    it('handles selective resets', function()
      local state = { bold = true, italic = true, foreground = 'Red' }

      ansi.update_ansi_state(state, '22')
      assert.is_false(state.bold)
      assert.is_true(state.italic)
      assert.equals('Red', state.foreground)

      ansi.update_ansi_state(state, '39')
      assert.is_false(state.bold)
      assert.is_true(state.italic)
      assert.is_nil(state.foreground)
    end)
  end)

  describe('setup_highlight_groups', function()
    it('creates highlight groups with fallback colors when terminal colors are nil', function()
      local original_colors = {}
      for i = 0, 15 do
        original_colors[i] = vim.g['terminal_color_' .. i]
        vim.g['terminal_color_' .. i] = nil
      end

      ansi.setup_highlight_groups()

      local highlight = vim.api.nvim_get_hl(0, { name = 'CpAnsiRed' })
      -- When 'NONE' is set, nvim_get_hl returns nil for that field
      assert.is_nil(highlight.fg)

      for i = 0, 15 do
        vim.g['terminal_color_' .. i] = original_colors[i]
      end
    end)

    it('creates highlight groups with proper colors when terminal colors are set', function()
      vim.g.terminal_color_1 = '#ff0000'

      ansi.setup_highlight_groups()

      local highlight = vim.api.nvim_get_hl(0, { name = 'CpAnsiRed' })
      assert.equals(0xff0000, highlight.fg)
    end)
  end)
end)
