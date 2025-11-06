#!/usr/bin/env python3

import asyncio
import json
import re
import sys
import time
from typing import Any

import backoff
import httpx
import requests
from bs4 import BeautifulSoup, Tag
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

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

MIB_TO_MB = 1.048576
BASE_URL = "https://atcoder.jp"
ARCHIVE_URL = f"{BASE_URL}/contests/archive"
TIMEOUT_SECONDS = 30
HEADERS = {
    "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
}
RETRY_STATUS = {429, 502, 503, 504}
FATAL_STATUS = {400, 401, 403, 404, 410}

_session = requests.Session()
_adapter = HTTPAdapter(
    pool_connections=100,
    pool_maxsize=100,
    max_retries=Retry(total=0),
)
_session.mount("https://", _adapter)
_session.mount("http://", _adapter)


def _give_up_requests(exc: Exception) -> bool:
    if isinstance(exc, requests.HTTPError) and exc.response is not None:
        return exc.response.status_code in FATAL_STATUS
    return False


def _retry_after_requests(details):
    exc = details.get("exception")
    if isinstance(exc, requests.HTTPError) and exc.response is not None:
        ra = exc.response.headers.get("Retry-After")
        if ra:
            try:
                time.sleep(max(0.0, float(ra)))
            except ValueError:
                pass


@backoff.on_exception(
    backoff.expo,
    (requests.ConnectionError, requests.Timeout, requests.HTTPError),
    max_tries=5,
    jitter=backoff.full_jitter,
    giveup=_give_up_requests,
    on_backoff=_retry_after_requests,
)
def _fetch(url: str) -> str:
    r = _session.get(url, headers=HEADERS, timeout=TIMEOUT_SECONDS, verify=False)
    if r.status_code in RETRY_STATUS:
        raise requests.HTTPError(response=r)
    r.raise_for_status()
    return r.text


def _giveup_httpx(exc: Exception) -> bool:
    return (
        isinstance(exc, httpx.HTTPStatusError)
        and exc.response is not None
        and (exc.response.status_code in FATAL_STATUS)
    )


@backoff.on_exception(
    backoff.expo,
    (httpx.ConnectError, httpx.ReadTimeout, httpx.HTTPStatusError),
    max_tries=5,
    jitter=backoff.full_jitter,
    giveup=_giveup_httpx,
)
async def _get_async(client: httpx.AsyncClient, url: str) -> str:
    r = await client.get(url, headers=HEADERS, timeout=TIMEOUT_SECONDS)
    r.raise_for_status()
    return r.text


def _text_from_pre(pre: Tag) -> str:
    return (
        pre.get_text(separator="\n", strip=False)
        .replace("\r", "")
        .replace("\xa0", " ")
        .rstrip("\n")
    )


def _parse_last_page(html: str) -> int:
    soup = BeautifulSoup(html, "html.parser")
    nav = soup.select_one("ul.pagination")
    if not nav:
        return 1
    nums = []
    for a in nav.select("a"):
        s = a.get_text(strip=True)
        if s.isdigit():
            nums.append(int(s))
    return max(nums) if nums else 1


def _parse_archive_contests(html: str) -> list[ContestSummary]:
    soup = BeautifulSoup(html, "html.parser")
    tbody = soup.select_one("table.table-default tbody") or soup.select_one("tbody")
    if not tbody:
        return []
    out: list[ContestSummary] = []
    for tr in tbody.select("tr"):
        a = tr.select_one("a[href^='/contests/']")
        if not a:
            continue
        href_attr = a.get("href")
        if not isinstance(href_attr, str):
            continue
        m = re.search(r"/contests/([^/?#]+)", href_attr)
        if not m:
            continue
        cid = m.group(1)
        name = a.get_text(strip=True)
        out.append(ContestSummary(id=cid, name=name, display_name=name))
    return out


def _parse_tasks_list(html: str) -> list[dict[str, str]]:
    soup = BeautifulSoup(html, "html.parser")
    tbody = soup.select_one("table tbody")
    if not tbody:
        return []
    rows: list[dict[str, str]] = []
    for tr in tbody.select("tr"):
        tds = tr.select("td")
        if len(tds) < 2:
            continue
        letter = tds[0].get_text(strip=True)
        a = tds[1].select_one("a[href*='/tasks/']")
        if not a:
            continue
        href_attr = a.get("href")
        if not isinstance(href_attr, str):
            continue
        m = re.search(r"/contests/[^/]+/tasks/([^/?#]+)", href_attr)
        if not m:
            continue
        slug = m.group(1)
        title = a.get_text(strip=True)
        rows.append({"letter": letter, "title": title, "slug": slug})
    return rows


def _extract_problem_info(html: str) -> tuple[int, float, bool]:
    soup = BeautifulSoup(html, "html.parser")
    txt = soup.get_text(" ", strip=True)
    timeout_ms = 0
    memory_mb = 0.0
    ts = re.search(r"Time\s*Limit:\s*([\d.]+)\s*sec", txt, flags=re.I)
    if ts:
        timeout_ms = int(float(ts.group(1)) * 1000)
    ms = re.search(r"Memory\s*Limit:\s*(\d+)\s*MiB", txt, flags=re.I)
    if ms:
        memory_mb = float(ms.group(1)) * MIB_TO_MB
    div = soup.select_one("#problem-statement")
    txt = div.get_text(" ", strip=True) if div else soup.get_text(" ", strip=True)
    interactive = "This is an interactive" in txt
    return timeout_ms, memory_mb, interactive


def _extract_samples(html: str) -> list[TestCase]:
    soup = BeautifulSoup(html, "html.parser")
    root = soup.select_one("#task-statement") or soup
    inputs: dict[str, str] = {}
    outputs: dict[str, str] = {}
    for h in root.find_all(re.compile(r"h[2-4]")):
        title = h.get_text(" ", strip=True)
        pre = h.find_next("pre")
        if not pre:
            continue
        t = _text_from_pre(pre)
        mi = re.search(r"Sample\s*Input\s*(\d+)", title, flags=re.I)
        mo = re.search(r"Sample\s*Output\s*(\d+)", title, flags=re.I)
        if mi:
            inputs[mi.group(1)] = t.strip()
        elif mo:
            outputs[mo.group(1)] = t.strip()
    cases: list[TestCase] = []
    for k in sorted(set(inputs) & set(outputs), key=lambda s: int(s)):
        cases.append(TestCase(input=inputs[k], expected=outputs[k]))
    return cases


def _scrape_tasks_sync(contest_id: str) -> list[dict[str, str]]:
    html = _fetch(f"{BASE_URL}/contests/{contest_id}/tasks")
    return _parse_tasks_list(html)


def _scrape_problem_page_sync(contest_id: str, slug: str) -> dict[str, Any]:
    html = _fetch(f"{BASE_URL}/contests/{contest_id}/tasks/{slug}")
    try:
        tests = _extract_samples(html)
    except Exception:
        tests = []
    timeout_ms, memory_mb, interactive = _extract_problem_info(html)
    return {
        "tests": tests,
        "timeout_ms": timeout_ms,
        "memory_mb": memory_mb,
        "interactive": interactive,
    }


def _to_problem_summaries(rows: list[dict[str, str]]) -> list[ProblemSummary]:
    out: list[ProblemSummary] = []
    for r in rows:
        letter = (r.get("letter") or "").strip().upper()
        title = r.get("title") or ""
        if not letter:
            continue
        pid = letter.lower()
        out.append(ProblemSummary(id=pid, name=title))
    return out


async def _fetch_all_contests_async() -> list[ContestSummary]:
    async with httpx.AsyncClient(
        limits=httpx.Limits(max_connections=100, max_keepalive_connections=100),
        verify=False,
    ) as client:
        first_html = await _get_async(client, ARCHIVE_URL)
        last = _parse_last_page(first_html)
        out = _parse_archive_contests(first_html)
        if last <= 1:
            return out
        tasks = [
            asyncio.create_task(_get_async(client, f"{ARCHIVE_URL}?page={p}"))
            for p in range(2, last + 1)
        ]
        for coro in asyncio.as_completed(tasks):
            html = await coro
            out.extend(_parse_archive_contests(html))
        return out


class AtcoderScraper(BaseScraper):
    @property
    def platform_name(self) -> str:
        return "atcoder"

    async def scrape_contest_metadata(self, contest_id: str) -> MetadataResult:
        async def impl(cid: str) -> MetadataResult:
            try:
                rows = await asyncio.to_thread(_scrape_tasks_sync, cid)
            except requests.HTTPError as e:
                if e.response is not None and e.response.status_code == 404:
                    return self._create_metadata_error(
                        f"No problems found for contest {cid}", cid
                    )
                raise

            problems = _to_problem_summaries(rows)
            if not problems:
                return self._create_metadata_error(
                    f"No problems found for contest {cid}", cid
                )

            return MetadataResult(
                success=True,
                error="",
                contest_id=cid,
                problems=problems,
                url=f"https://atcoder.jp/contests/{contest_id}/tasks/{contest_id}_%s",
            )

        return await self._safe_execute("metadata", impl, contest_id)

    async def scrape_contest_list(self) -> ContestListResult:
        async def impl() -> ContestListResult:
            try:
                contests = await _fetch_all_contests_async()
            except Exception as e:
                return self._create_contests_error(str(e))
            if not contests:
                return self._create_contests_error("No contests found")
            return ContestListResult(success=True, error="", contests=contests)

        return await self._safe_execute("contests", impl)

    async def stream_tests_for_category_async(self, category_id: str) -> None:
        rows = await asyncio.to_thread(_scrape_tasks_sync, category_id)

        async def emit(row: dict[str, str]) -> None:
            letter = (row.get("letter") or "").strip().lower()
            slug = row.get("slug") or ""
            if not letter or not slug:
                return
            data = await asyncio.to_thread(_scrape_problem_page_sync, category_id, slug)
            tests: list[TestCase] = data.get("tests", [])
            combined_input = "\n".join(t.input for t in tests) if tests else ""
            combined_expected = "\n".join(t.expected for t in tests) if tests else ""
            print(
                json.dumps(
                    {
                        "problem_id": letter,
                        "combined": {
                            "input": combined_input,
                            "expected": combined_expected,
                        },
                        "tests": [
                            {"input": t.input, "expected": t.expected} for t in tests
                        ],
                        "timeout_ms": data.get("timeout_ms", 0),
                        "memory_mb": data.get("memory_mb", 0),
                        "interactive": bool(data.get("interactive")),
                        "multi_test": False,
                    }
                ),
                flush=True,
            )

        await asyncio.gather(*(emit(r) for r in rows))


async def main_async() -> int:
    if len(sys.argv) < 2:
        result = MetadataResult(
            success=False,
            error="Usage: atcoder.py metadata <contest_id> OR atcoder.py tests <contest_id> OR atcoder.py contests",
            url="",
        )
        print(result.model_dump_json())
        return 1

    mode: str = sys.argv[1]
    scraper = AtcoderScraper()

    if mode == "metadata":
        if len(sys.argv) != 3:
            result = MetadataResult(
                success=False,
                error="Usage: atcoder.py metadata <contest_id>",
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
                error="Usage: atcoder.py tests <contest_id>",
                problem_id="",
                combined=CombinedTest(input="", expected=""),
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
                success=False, error="Usage: atcoder.py contests"
            )
            print(contest_result.model_dump_json())
            return 1
        contest_result = await scraper.scrape_contest_list()
        print(contest_result.model_dump_json())
        return 0 if contest_result.success else 1

    result = MetadataResult(
        success=False,
        error="Unknown mode. Use 'metadata <contest_id>', 'tests <contest_id>', or 'contests'",
        url="",
    )
    print(result.model_dump_json())
    return 1


def main() -> None:
    sys.exit(asyncio.run(main_async()))


if __name__ == "__main__":
    main()
