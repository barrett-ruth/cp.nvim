# cp.nvim

neovim plugin for competitive programming.

https://private-user-images.githubusercontent.com/62671086/489116291-391976d1-c2f4-49e6-a79d-13ff05e9be86.mp4?jwt=eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3NTc3NDQ1ODEsIm5iZiI6MTc1Nzc0NDI4MSwicGF0aCI6Ii82MjY3MTA4Ni80ODkxMTYyOTEtMzkxOTc2ZDEtYzJmNC00OWU2LWE3OWQtMTNmZjA1ZTliZTg2Lm1wND9YLUFtei1BbGdvcml0aG09QVdTNC1ITUFDLVNIQTI1NiZYLUFtei1DcmVkZW50aWFsPUFLSUFWQ09EWUxTQTUzUFFLNFpBJTJGMjAyNTA5MTMlMkZ1cy1lYXN0LTElMkZzMyUyRmF3czRfcmVxdWVzdCZYLUFtei1EYXRlPTIwMjUwOTEzVDA2MTgwMVomWC1BbXotRXhwaXJlcz0zMDAmWC1BbXotU2lnbmF0dXJlPWI0Zjc0YmQzNWIzNGZkM2VjZjM3NGM0YmZmM2I3MmJkZGQ0YTczYjIxMTFiODc3MjQyMzY3ODc2ZTUxZDRkMzkmWC1BbXotU2lnbmVkSGVhZGVycz1ob3N0In0.MBK5q_Zxr0gWuzfjwmSbB7P7dtWrATrT5cDOosdPRuQ

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
