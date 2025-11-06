#!/usr/bin/env python3

import asyncio
import json
import re
import sys
from typing import Any

import httpx

from .base import BaseScraper
from .models import (
    CombinedTest,
    ContestListResult,
    ContestSummary,
    MetadataResult,
    ProblemSummary,
    TestCase,
    TestsResult,
)

BASE_URL = "https://cses.fi"
INDEX_PATH = "/problemset"
TASK_PATH = "/problemset/task/{id}"
HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
}
TIMEOUT_S = 15.0
CONNECTIONS = 8


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
    r'<h2>(?P<cat>[^<]+)</h2>\s*<ul\s+class="task-list">(?P<body>.*?)</ul>',
    re.DOTALL,
)
TASK_LINK_RE = re.compile(
    r'<li\s+class="task">\s*<a\s+href="/problemset/task/(?P<id>\d+)/?">(?P<title>[^<]+)</a\s*>',
    re.DOTALL,
)

TITLE_RE = re.compile(
    r'<div\s+class="title-block">.*?<h1>(?P<title>[^<]+)</h1>', re.DOTALL
)
TIME_RE = re.compile(r"<li>\s*<b>Time limit:</b>\s*([0-9.]+)\s*s\s*</li>")
MEM_RE = re.compile(r"<li>\s*<b>Memory limit:</b>\s*(\d+)\s*MB\s*</li>")
SIDEBAR_CAT_RE = re.compile(
    r'<div\s+class="nav sidebar">.*?<h4>(?P<cat>[^<]+)</h4>', re.DOTALL
)

MD_BLOCK_RE = re.compile(r'<div\s+class="md">(.*?)</div>', re.DOTALL | re.IGNORECASE)
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


def _extract_problem_info(html: str) -> tuple[int, int, bool]:
    tm = TIME_RE.search(html)
    mm = MEM_RE.search(html)
    t = int(round(float(tm.group(1)) * 1000)) if tm else 0
    m = int(mm.group(1)) if mm else 0
    md = MD_BLOCK_RE.search(html)
    interactive = False
    if md:
        body = md.group(1)
        interactive = "This is an interactive problem." in body
    return t, m, interactive


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
                url="",
            )
        return MetadataResult(
            success=True,
            error="",
            contest_id=contest_id,
            problems=problems,
            url="https://cses.fi/problemset/task/%s",
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
                        timeout_ms, memory_mb, interactive = _extract_problem_info(html)
                    except Exception:
                        tests = []
                        timeout_ms, memory_mb, interactive = 0, 0, False

                    combined_input = "\n".join(t.input for t in tests) if tests else ""
                    combined_expected = (
                        "\n".join(t.expected for t in tests) if tests else ""
                    )

                    return {
                        "problem_id": pid,
                        "combined": {
                            "input": combined_input,
                            "expected": combined_expected,
                        },
                        "tests": [
                            {"input": t.input, "expected": t.expected} for t in tests
                        ],
                        "timeout_ms": timeout_ms,
                        "memory_mb": memory_mb,
                        "interactive": interactive,
                        "multi_test": False,
                    }

            tasks = [run_one(p.id) for p in problems]
            for coro in asyncio.as_completed(tasks):
                payload = await coro
                print(json.dumps(payload), flush=True)


async def main_async() -> int:
    if len(sys.argv) < 2:
        result = MetadataResult(
            success=False,
            error="Usage: cses.py metadata <category_id> OR cses.py tests <category> OR cses.py contests",
            url="",
        )
        print(result.model_dump_json())
        return 1

    mode: str = sys.argv[1]
    scraper = CSESScraper()

    if mode == "metadata":
        if len(sys.argv) != 3:
            result = MetadataResult(
                success=False,
                error="Usage: cses.py metadata <category_id>",
                url="",
            )
            print(result.model_dump_json())
            return 1
        category_id = sys.argv[2]
        result = await scraper.scrape_contest_metadata(category_id)
        print(result.model_dump_json())
        return 0 if result.success else 1

    if mode == "tests":
        if len(sys.argv) != 3:
            tests_result = TestsResult(
                success=False,
                error="Usage: cses.py tests <category>",
                problem_id="",
                combined=CombinedTest(input="", expected=""),
                tests=[],
                timeout_ms=0,
                memory_mb=0,
            )
            print(tests_result.model_dump_json())
            return 1
        category = sys.argv[2]
        await scraper.stream_tests_for_category_async(category)
        return 0

    if mode == "contests":
        if len(sys.argv) != 2:
            contest_result = ContestListResult(
                success=False, error="Usage: cses.py contests"
            )
            print(contest_result.model_dump_json())
            return 1
        contest_result = await scraper.scrape_contest_list()
        print(contest_result.model_dump_json())
        return 0 if contest_result.success else 1

    result = MetadataResult(
        success=False,
        error=f"Unknown mode: {mode}. Use 'metadata <category>', 'tests <category>', or 'contests'",
        url="",
    )
    print(result.model_dump_json())
    return 1


def main() -> None:
    sys.exit(asyncio.run(main_async()))


if __name__ == "__main__":
    main()
