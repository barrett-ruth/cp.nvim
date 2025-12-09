# cp.nvim

**The definitive competitive programming environment for Neovim**

Scrape problems, run tests, and debug solutions across multiple platforms with
zero configuration.

https://github.com/user-attachments/assets/e81d8dfb-578f-4a79-9989-210164fc0148

## Features

- **Multi-platform support**: AtCoder, CodeChef, Codeforces, and CSES
- **Automatic problem setup**: Scrape test cases and metadata in seconds
- **Dual view modes**: Lightweight I/O view for quick feedback, full panel for
  detailed analysis
- **Test case management**: Quickly view, edit, add, & remove test cases
- **Rich test output**: 256 color ANSI support for compiler errors and program
  output
- **Language agnostic**: Works with any language
- **Diff viewer**: Compare expected vs actual output with 3 diff modes

## Optional Dependencies

- [uv](https://docs.astral.sh/uv/) for problem scraping
- GNU [time](https://www.gnu.org/software/time/) and
  [timeout](https://www.gnu.org/software/coreutils/manual/html_node/timeout-invocation.html)

## Quick Start

cp.nvim follows a simple principle: **solve locally, submit remotely**.

### Basic Usage

1. Find a contest or problem
2. Set up contests locally

   ```
   :CP codeforces 1848
   ```

3. Code and test

   ```
   :CP run
   ```

4. Navigate between problems

   ```
   :CP next
   :CP prev
   :CP e1
   ```

5. Debug and edit test cases

```
:CP edit
:CP panel --debug
```

5. Submit on the original website

## Documentation

```vim
:help cp.nvim
```

See
[my config](https://github.com/barrett-ruth/dots/blob/main/nvim/lua/plugins/cp.lua)
for the setup in the video shown above.

## Similar Projects

- [competitest.nvim](https://github.com/xeluxee/competitest.nvim)
- [assistant.nvim](https://github.com/A7Lavinraj/assistant.nvim)
