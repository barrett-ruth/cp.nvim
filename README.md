# cp.nvim

**The definitive competitive programming environment for Neovim**

Scrape problems, run tests, and debug solutions across multiple platforms with zero configuration.

https://github.com/user-attachments/assets/50b19481-8e6d-47b4-bebc-15e16c61a9c9

## Features

- **Multi-platform support**: AtCoder, Codeforces, CSES with consistent interface
- **Automatic problem setup**: Scrape test cases and metadata in seconds
- **Rich test output**: 256 color ANSI support for compiler errors and program output
- **Language agnostic**: Works with any language
- **Diff viewer**: Compare expected vs actual output with 3 diff modes

## Optional Dependencies

- [uv](https://docs.astral.sh/uv/) for problem scraping
- GNU [time](https://www.gnu.org/software/time/) and [timeout](https://www.gnu.org/software/coreutils/manual/html_node/timeout-invocation.html)

## Quick Start

cp.nvim follows a simple principle: **solve locally, submit remotely**.

### Basic Usage

1. **Find a contest or problem** on the judge website
2. **Set up locally** with `:CP <platform> <contest>`

   ```
   :CP codeforces 1848
   ```

3. **Code and test** with instant feedback and rich diffs

   ```
   :CP run
   ```

4. **Navigate between problems**

   ```
   :CP next
   :CP prev
   :CP e1
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
