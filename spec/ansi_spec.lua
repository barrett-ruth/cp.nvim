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

    it('creates correct highlight for colored text', function()
      local input = 'Hello \027[31mworld\027[0m!'
      local result = ansi.parse_ansi_text(input)

      assert.equals(1, #result.highlights)
      local highlight = result.highlights[1]
      assert.equals(0, highlight.line)
      assert.equals(6, highlight.col_start)
      assert.equals(11, highlight.col_end)
      assert.equals('CpAnsiRed', highlight.highlight_group)
    end)

    it('handles multiple colors on same line', function()
      local input = '\027[31mred\027[0m and \027[32mgreen\027[0m'
      local result = ansi.parse_ansi_text(input)

      assert.equals('red and green', table.concat(result.lines, '\n'))
      assert.equals(2, #result.highlights)

      local red_highlight = result.highlights[1]
      assert.equals(0, red_highlight.col_start)
      assert.equals(3, red_highlight.col_end)
      assert.equals('CpAnsiRed', red_highlight.highlight_group)

      local green_highlight = result.highlights[2]
      assert.equals(8, green_highlight.col_start)
      assert.equals(13, green_highlight.col_end)
      assert.equals('CpAnsiGreen', green_highlight.highlight_group)
    end)

    it('handles multiline colored text', function()
      local input = '\027[31mline1\nline2\027[0m'
      local result = ansi.parse_ansi_text(input)

      assert.equals('line1\nline2', table.concat(result.lines, '\n'))
      assert.equals(2, #result.highlights)

      local line1_highlight = result.highlights[1]
      assert.equals(0, line1_highlight.line)
      assert.equals(0, line1_highlight.col_start)
      assert.equals(5, line1_highlight.col_end)

      local line2_highlight = result.highlights[2]
      assert.equals(1, line2_highlight.line)
      assert.equals(0, line2_highlight.col_start)
      assert.equals(5, line2_highlight.col_end)
    end)

    it('handles compiler-like output', function()
      local input =
        "error.cpp:10:5: \027[1m\027[31merror:\027[0m\027[1m 'undefined' was not declared\027[0m"
      local result = ansi.parse_ansi_text(input)

      local clean_text = table.concat(result.lines, '\n')
      assert.is_true(clean_text:find("error.cpp:10:5: error: 'undefined' was not declared") ~= nil)
      assert.is_false(clean_text:find('\027') ~= nil)
    end)
  end)

  describe('ansi_code_to_highlight', function()
    it('maps standard colors', function()
      assert.equals('CpAnsiRed', ansi.ansi_code_to_highlight('31'))
      assert.equals('CpAnsiGreen', ansi.ansi_code_to_highlight('32'))
      assert.equals('CpAnsiYellow', ansi.ansi_code_to_highlight('33'))
    end)

    it('handles reset codes', function()
      assert.is_nil(ansi.ansi_code_to_highlight('0'))
      assert.is_nil(ansi.ansi_code_to_highlight(''))
    end)

    it('handles unknown codes', function()
      assert.is_nil(ansi.ansi_code_to_highlight('99'))
    end)
  end)
end)
