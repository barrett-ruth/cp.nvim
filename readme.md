# cp.nvim

neovim plugin for competitive programming.

> Sample test data from [codeforces](https://codeforces.com) is scraped via [cloudscraper](https://github.com/VeNoMouS/cloudscraper). Use at your own risk.

## Features

- Support for multiple online judges ([AtCoder](https://atcoder.jp/), [Codeforces](https://codeforces.com/), [CSES](https://cses.fi))
- Automatic problem scraping and test case management
- Integrated build, run, and debug commands
- Diff mode for comparing output with expected results
- LuaSnip integration for contest-specific snippets

## Requirements

- Neovim 0.10.0+
- [uv](https://docs.astral.sh/uv/): problem scraping (optional)
- [LuaSnip](https://github.com/L3MON4D3/LuaSnip): contest-specific snippets (optional)

## Documentation

```vim
:help cp.nvim
```

## TODO

- better highlighting
- test case management
- USACO support
