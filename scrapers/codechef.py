#!/usr/bin/env python3

import asyncio
import json
import re
import sys
from typing import Any

import httpx
from scrapling.fetchers import StealthyFetcher

from .base import BaseScraper
from .models import (
    ContestListResult,
    ContestSummary,
    MetadataResult,
    ProblemSummary,
    TestCase,
    TestsResult,
)

BASE_URL = "https://www.codechef.com"
API_CONTESTS_ALL = "/api/list/contests/all"
API_CONTEST = "/api/contests/{contest_id}"
API_PROBLEM = "/api/contests/{contest_id}/problems/{problem_id}"
PROBLEM_URL = "https://www.codechef.com/problems/{problem_id}"

HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
}
TIMEOUT_S = 15.0
CONNECTIONS = 8

MEMORY_LIMIT_RE = re.compile(r"Memory\s+[Ll]imit[:\s]+([0-9.]+)\s*MB", re.IGNORECASE)


async def fetch_json(client: httpx.AsyncClient, path: str) -> dict:
    r = await client.get(BASE_URL + path, headers=HEADERS, timeout=TIMEOUT_S)
    r.raise_for_status()
    return r.json()


def _extract_memory_limit(html: str) -> float:
    m = MEMORY_LIMIT_RE.search(html)
    return float(m.group(1)) if m else 256.0


def _fetch_html_sync(url: str) -> str:
    response = StealthyFetcher.fetch(url, headless=True, network_idle=True)
    return str(response.body)


def get_div4_contest_id(contest_id: str) -> str:
    return f"{contest_id}D"


class CodeChefScraper(BaseScraper):
    @property
    def platform_name(self) -> str:
        return "codechef"

    async def scrape_contest_metadata(self, contest_id: str) -> MetadataResult:
        div4_id = get_div4_contest_id(contest_id)
        async with httpx.AsyncClient() as client:
            try:
                data = await fetch_json(client, API_CONTEST.format(contest_id=div4_id))
            except httpx.HTTPStatusError as e:
                return self._create_metadata_error(
                    f"Failed to fetch contest {contest_id}: {e}", contest_id
                )

        if not data.get("problems"):
            return self._create_metadata_error(
                f"No problems found for contest {contest_id}", contest_id
            )

        problems = []
        for problem_code, problem_data in data["problems"].items():
            problems.append(
                ProblemSummary(
                    id=problem_code,
                    name=problem_data.get("name", problem_code),
                )
            )

        return MetadataResult(
            success=True,
            error="",
            contest_id=contest_id,
            problems=problems,
            url=f"{BASE_URL}/{contest_id}",
        )

    async def scrape_contest_list(self) -> ContestListResult:
        async with httpx.AsyncClient() as client:
            try:
                data = await fetch_json(client, API_CONTESTS_ALL)
            except httpx.HTTPStatusError as e:
                return self._create_contests_error(f"Failed to fetch contests: {e}")

        all_contests = data.get("future_contests", []) + data.get("past_contests", [])

        max_num = 0
        contest_names = {}

        for contest in all_contests:
            contest_code = contest.get("contest_code", "")
            if contest_code.startswith("START"):
                match = re.match(r"START(\d+)", contest_code)
                if match:
                    num = int(match.group(1))
                    max_num = max(max_num, num)
                    contest_names[contest_code] = contest.get(
                        "contest_name", contest_code
                    )

        if max_num == 0:
            return self._create_contests_error("No Starters contests found")

        contests = []
        for i in range(1, max_num + 1):
            contest_id = f"START{i}"
            name = contest_names.get(contest_id, f"Starters {i}")
            contests.append(
                ContestSummary(
                    id=contest_id,
                    name=name,
                    display_name=name,
                )
            )

        return ContestListResult(success=True, error="", contests=contests)

    async def stream_tests_for_category_async(self, contest_id: str) -> None:
        div4_id = get_div4_contest_id(contest_id)

        async with httpx.AsyncClient(
            limits=httpx.Limits(max_connections=CONNECTIONS)
        ) as client:
            try:
                contest_data = await fetch_json(
                    client, API_CONTEST.format(contest_id=div4_id)
                )
            except Exception:
                return

            problems = contest_data.get("problems", {})
            if not problems:
                return

            sem = asyncio.Semaphore(CONNECTIONS)

            async def run_one(problem_code: str) -> dict[str, Any]:
                async with sem:
                    try:
                        problem_data = await fetch_json(
                            client,
                            API_PROBLEM.format(
                                contest_id=div4_id, problem_id=problem_code
                            ),
                        )

                        sample_tests = (
                            problem_data.get("problemComponents", {}).get(
                                "sampleTestCases", []
                            )
                            or []
                        )
                        tests = [
                            TestCase(
                                input=t.get("input", "").strip(),
                                expected=t.get("output", "").strip(),
                            )
                            for t in sample_tests
                            if not t.get("isDeleted", False)
                        ]

                        time_limit_str = problem_data.get("max_timelimit", "1")
                        timeout_ms = int(float(time_limit_str) * 1000)

                        problem_url = PROBLEM_URL.format(problem_id=problem_code)
                        loop = asyncio.get_event_loop()
                        html = await loop.run_in_executor(
                            None, _fetch_html_sync, problem_url
                        )
                        memory_mb = _extract_memory_limit(html)

                        interactive = False

                    except Exception:
                        tests = []
                        timeout_ms = 1000
                        memory_mb = 256.0
                        interactive = False

                    return {
                        "problem_id": problem_code,
                        "tests": [
                            {"input": t.input, "expected": t.expected} for t in tests
                        ],
                        "timeout_ms": timeout_ms,
                        "memory_mb": memory_mb,
                        "interactive": interactive,
                    }

            tasks = [run_one(problem_code) for problem_code in problems.keys()]
            for coro in asyncio.as_completed(tasks):
                payload = await coro
                print(json.dumps(payload), flush=True)


async def main_async() -> int:
    if len(sys.argv) < 2:
        result = MetadataResult(
            success=False,
            error="Usage: codechef.py metadata <contest_id> OR codechef.py tests <contest_id> OR codechef.py contests",
            url="",
        )
        print(result.model_dump_json())
        return 1

    mode: str = sys.argv[1]
    scraper = CodeChefScraper()

    if mode == "metadata":
        if len(sys.argv) != 3:
            result = MetadataResult(
                success=False,
                error="Usage: codechef.py metadata <contest_id>",
                url="",
            )
            print(result.model_dump_json())
            return 1
        contest_id = sys.argv[2]
        result = await scraper.scrape_contest_metadata(contest_id)
        print(result.model_dump_json())
        return 0 if result.success else 1

    if mode == "tests":
        if len(sys.argv) != 3:
            tests_result = TestsResult(
                success=False,
                error="Usage: codechef.py tests <contest_id>",
                problem_id="",
                tests=[],
                timeout_ms=0,
                memory_mb=0,
            )
            print(tests_result.model_dump_json())
            return 1
        contest_id = sys.argv[2]
        await scraper.stream_tests_for_category_async(contest_id)
        return 0

    if mode == "contests":
        if len(sys.argv) != 2:
            contest_result = ContestListResult(
                success=False, error="Usage: codechef.py contests"
            )
            print(contest_result.model_dump_json())
            return 1
        contest_result = await scraper.scrape_contest_list()
        print(contest_result.model_dump_json())
        return 0 if contest_result.success else 1

    result = MetadataResult(
        success=False,
        error=f"Unknown mode: {mode}. Use 'metadata <contest_id>', 'tests <contest_id>', or 'contests'",
        url="",
    )
    print(result.model_dump_json())
    return 1


def main() -> None:
    sys.exit(asyncio.run(main_async()))


if __name__ == "__main__":
    main()
