#!/usr/bin/env python3

import asyncio
import json
import re
import sys
from dataclasses import asdict
from typing import Any

import httpx

from .base import BaseScraper
from .models import (
    ContestListResult,
    ContestSummary,
    MetadataResult,
    ProblemSummary,
    TestCase,
    TestsResult,
)

BASE_URL = "https://cses.fi"
INDEX_PATH = "/problemset/list"
TASK_PATH = "/problemset/task/{id}"
HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
}
TIMEOUT_S = 15.0
CONNECTIONS = 8


def _run(coro):
    return asyncio.run(coro)


def normalize_category_name(category_name: str) -> str:
    return category_name.lower().replace(" ", "_").replace("&", "and")


def snake_to_title(name: str) -> str:
    small_words = {
        "a",
        "an",
        "the",
        "and",
        "but",
        "or",
        "nor",
        "for",
        "so",
        "yet",
        "at",
        "by",
        "in",
        "of",
        "on",
        "per",
        "to",
        "vs",
        "via",
    }
    words: list[str] = name.split("_")
    n = len(words)

    def fix_word(i_word):
        i, word = i_word
        lw = word.lower()
        return lw.capitalize() if i == 0 or i == n - 1 or lw not in small_words else lw

    return " ".join(map(fix_word, enumerate(words)))


async def fetch_text(client: httpx.AsyncClient, path: str) -> str:
    r = await client.get(BASE_URL + path, headers=HEADERS, timeout=TIMEOUT_S)
    r.raise_for_status()
    return r.text


CATEGORY_BLOCK_RE = re.compile(
    r'<h2>(?P<cat>[^<]+)</h2>\s*<ul class="task-list">(?P<body>.*?)</ul>',
    re.DOTALL,
)
TASK_LINK_RE = re.compile(
    r'<li class="task"><a href="/problemset/task/(?P<id>\d+)/?">(?P<title>[^<]+)</a>',
    re.DOTALL,
)

TITLE_RE = re.compile(
    r'<div class="title-block">.*?<h1>(?P<title>[^<]+)</h1>', re.DOTALL
)
TIME_RE = re.compile(r"<li><b>Time limit:</b>\s*([0-9.]+)\s*s</li>")
MEM_RE = re.compile(r"<li><b>Memory limit:</b>\s*(\d+)\s*MB</li>")
SIDEBAR_CAT_RE = re.compile(
    r'<div class="nav sidebar">.*?<h4>(?P<cat>[^<]+)</h4>', re.DOTALL
)

MD_BLOCK_RE = re.compile(r'<div class="md">(.*?)</div>', re.DOTALL | re.IGNORECASE)
EXAMPLE_SECTION_RE = re.compile(
    r"<h[1-6][^>]*>\s*example[s]?:?\s*</h[1-6]>\s*(?P<section>.*?)(?=<h[1-6][^>]*>|$)",
    re.DOTALL | re.IGNORECASE,
)
LABELED_IO_RE = re.compile(
    r"input\s*:\s*</p>\s*<pre>(?P<input>.*?)</pre>.*?output\s*:\s*</p>\s*<pre>(?P<output>.*?)</pre>",
    re.DOTALL | re.IGNORECASE,
)
PRE_RE = re.compile(r"<pre>(.*?)</pre>", re.DOTALL | re.IGNORECASE)


def parse_categories(html: str) -> list[ContestSummary]:
    out: list[ContestSummary] = []
    for m in CATEGORY_BLOCK_RE.finditer(html):
        cat = m.group("cat").strip()
        if cat == "General":
            continue
        out.append(
            ContestSummary(
                id=normalize_category_name(cat),
                name=cat,
                display_name=cat,
            )
        )
    return out


def parse_category_problems(category_id: str, html: str) -> list[ProblemSummary]:
    want = snake_to_title(category_id)
    for m in CATEGORY_BLOCK_RE.finditer(html):
        cat = m.group("cat").strip()
        if cat != want:
            continue
        body = m.group("body")
        return [
            ProblemSummary(id=mm.group("id"), name=mm.group("title"))
            for mm in TASK_LINK_RE.finditer(body)
        ]
    return []


def parse_limits(html: str) -> tuple[int, int]:
    tm = TIME_RE.search(html)
    mm = MEM_RE.search(html)
    t = int(round(float(tm.group(1)) * 1000)) if tm else 0
    m = int(mm.group(1)) if mm else 0
    return t, m


def parse_title(html: str) -> str:
    mt = TITLE_RE.search(html)
    return mt.group("title").strip() if mt else ""


def parse_category_from_sidebar(html: str) -> str | None:
    m = SIDEBAR_CAT_RE.search(html)
    return m.group("cat").strip() if m else None


def parse_tests(html: str) -> list[TestCase]:
    md = MD_BLOCK_RE.search(html)
    if not md:
        return []
    block = md.group(1)

    msec = EXAMPLE_SECTION_RE.search(block)
    section = msec.group("section") if msec else block

    mlabel = LABELED_IO_RE.search(section)
    if mlabel:
        a = mlabel.group("input").strip()
        b = mlabel.group("output").strip()
        return [TestCase(input=a, expected=b)]

    pres = PRE_RE.findall(section)
    if len(pres) >= 2:
        return [TestCase(input=pres[0].strip(), expected=pres[1].strip())]

    return []


def task_path(problem_id: str | int) -> str:
    return TASK_PATH.format(id=str(problem_id))


class CSESScraper(BaseScraper):
    @property
    def platform_name(self) -> str:
        return "cses"

    async def scrape_contest_metadata(self, contest_id: str) -> MetadataResult:
        async with httpx.AsyncClient() as client:
            html = await fetch_text(client, INDEX_PATH)
        problems = parse_category_problems(contest_id, html)
        if not problems:
            return MetadataResult(
                success=False,
                error=f"{self.platform_name}: No problems found for category: {contest_id}",
            )
        return MetadataResult(
            success=True, error="", contest_id=contest_id, problems=problems
        )

    async def scrape_problem_tests(
        self, contest_id: str, problem_id: str
    ) -> TestsResult:
        path = task_path(problem_id)
        async with httpx.AsyncClient() as client:
            html = await fetch_text(client, path)
        tests = parse_tests(html)
        timeout_ms, memory_mb = parse_limits(html)
        if not tests:
            return TestsResult(
                success=False,
                error=f"{self.platform_name}: No tests found for {problem_id}",
                problem_id=problem_id if problem_id.isdigit() else "",
                url=BASE_URL + path,
                tests=[],
                timeout_ms=timeout_ms,
                memory_mb=memory_mb,
            )
        return TestsResult(
            success=True,
            error="",
            problem_id=problem_id if problem_id.isdigit() else "",
            url=BASE_URL + path,
            tests=tests,
            timeout_ms=timeout_ms,
            memory_mb=memory_mb,
        )

    async def scrape_contest_list(self) -> ContestListResult:
        async with httpx.AsyncClient() as client:
            html = await fetch_text(client, INDEX_PATH)
        cats = parse_categories(html)
        if not cats:
            return ContestListResult(
                success=False, error=f"{self.platform_name}: No contests found"
            )
        return ContestListResult(success=True, error="", contests=cats)

    async def stream_tests_for_category_async(self, category_id: str) -> None:
        async with httpx.AsyncClient(
            limits=httpx.Limits(max_connections=CONNECTIONS)
        ) as client:
            index_html = await fetch_text(client, INDEX_PATH)
            problems = parse_category_problems(category_id, index_html)
            if not problems:
                return

            sem = asyncio.Semaphore(CONNECTIONS)

            async def run_one(pid: str) -> dict[str, Any]:
                async with sem:
                    try:
                        html = await fetch_text(client, task_path(pid))
                        tests = parse_tests(html)
                        timeout_ms, memory_mb = parse_limits(html)
                        if not tests:
                            return {
                                "problem_id": pid,
                                "error": f"{self.platform_name}: no tests found",
                            }
                        return {
                            "problem_id": pid,
                            "tests": [
                                {"input": t.input, "expected": t.expected}
                                for t in tests
                            ],
                            "timeout_ms": timeout_ms,
                            "memory_mb": memory_mb,
                            "interactive": False,
                        }
                    except Exception as e:
                        return {"problem_id": pid, "error": str(e)}

            tasks = [run_one(p.id) for p in problems]
            for coro in asyncio.as_completed(tasks):
                payload = await coro
                print(json.dumps(payload), flush=True)


async def main_async() -> int:
    if len(sys.argv) < 2:
        result = MetadataResult(
            success=False,
            error="Usage: cses.py metadata <category_id> OR cses.py tests <category> OR cses.py contests",
        )
        print(json.dumps(asdict(result)))
        return 1

    mode: str = sys.argv[1]
    scraper = CSESScraper()

    if mode == "metadata":
        if len(sys.argv) != 3:
            result = MetadataResult(
                success=False, error="Usage: cses.py metadata <category_id>"
            )
            print(json.dumps(asdict(result)))
            return 1
        category_id = sys.argv[2]
        result = await scraper.scrape_contest_metadata(category_id)
        print(json.dumps(asdict(result)))
        return 0 if result.success else 1

    if mode == "tests":
        if len(sys.argv) != 3:
            tests_result = TestsResult(
                success=False,
                error="Usage: cses.py tests <category>",
                problem_id="",
                url="",
                tests=[],
                timeout_ms=0,
                memory_mb=0,
            )
            print(json.dumps(asdict(tests_result)))
            return 1
        category = sys.argv[2]
        await scraper.stream_tests_for_category_async(category)
        return 0

    if mode == "contests":
        if len(sys.argv) != 2:
            contest_result = ContestListResult(
                success=False, error="Usage: cses.py contests"
            )
            print(json.dumps(asdict(contest_result)))
            return 1
        contest_result = await scraper.scrape_contest_list()
        print(json.dumps(asdict(contest_result)))
        return 0 if contest_result.success else 1

    result = MetadataResult(
        success=False,
        error=f"Unknown mode: {mode}. Use 'metadata <category>', 'tests <category>', or 'contests'",
    )
    print(json.dumps(asdict(result)))
    return 1


def main() -> None:
    sys.exit(asyncio.run(main_async()))


if __name__ == "__main__":
    main()
