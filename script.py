#!/usr/bin/env python3
from bs4 import BeautifulSoup
from scrapling.fetchers import StealthyFetcher

URL = "https://codeforces.com/contest/1974/problem/A"

page = StealthyFetcher.fetch(
    URL,
    headless=True,
    solve_cloudflare=True,
)

soup = BeautifulSoup(page.html_content, "html.parser")
title = soup.find("div", class_="title")
if title:
    print("Page fetched successfully. Problem title:", title.get_text(strip=True))
else:
    print("Page fetched but could not find problem title.")
