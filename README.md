# cp.nvim

**Fast, minimal competitive programming environment for Neovim**

Scrape problems, run tests, and debug solutions across multiple platforms with zero configuration.

> **Disclaimer**: cp.nvim webs crapes data from competitive programming platforms - use at your own risk.

https://github.com/user-attachments/assets/cb142535-fba0-4280-8f11-66ad1ca50ca9

## Features

- **Multi-platform support**: AtCoder, Codeforces, CSES with consistent interface
- **Automatic problem setup**: Scrape test cases and metadata in seconds
- **Rich test output**: ANSI color support for compiler errors and program output
- **Language agnostic**: Works with any compiled language
- **Template integration**: Contest-specific snippets via LuaSnip
- **Diff viewer**: Compare expected vs actual output with precision

## Optional Dependencies

- [uv](https://docs.astral.sh/uv/) for problem scraping
- [LuaSnip](https://github.com/L3MON4D3/LuaSnip) for templates

## Quick Start

cp.nvim follows a simple principle: **solve locally, submit remotely**.

### Basic Usage

1. **Find a problem** on the judge website
2. **Set up locally** with `:CP <platform> <contest> <problem>`

   ```
   :CP codeforces 1848 A
   ```

3. **Code and test** with instant feedback and rich diffs

   ```
   :CP run
   ```

4. **Navigate between problems**

   ```
   :CP next
   :CP prev
   ```

5. **Submit** on the original website

## Documentation

```vim
:help cp.nvim
```

See [my config](https://github.com/barrett-ruth/dots/blob/main/nvim/lua/plugins/cp.lua) for a relatively advanced setup.

## Similar Projects

- [competitest.nvim](https://github.com/xeluxee/competitest.nvim)
- [assistant.nvim](https://github.com/A7Lavinraj/assistant.nvim)
