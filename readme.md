# cp.nvim

A Neovim plugin for competitive programming.

## Features

- Support for multiple online judges (AtCoder, Codeforces, CSES, ICPC)
- Automatic problem scraping and test case management
- Integrated build, run, and debug commands
- Diff mode for comparing output with expected results
- LuaSnip integration for contest-specific snippets

## Requirements

- Neovim 0.9+
- `make` and a C++ compiler
- (Optional) [uv](https://docs.astral.sh/uv/) for problem scraping
- (Optional) [LuaSnip](https://github.com/L3MON4D3/LuaSnip) for snippets

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
    "barrett-ruth/cp.nvim",
    cmd = "CP",
    dependencies = {
        "L3MON4D3/LuaSnip",
    }
}
```

## Documentation

```vim
:help cp.nvim
```

## TODO

- vimdocs
- example video
- more flexible setup (more of a question of philosophy)
- USACO support
