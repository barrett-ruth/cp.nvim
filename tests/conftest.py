import asyncio
import importlib.util
import io
import json
import sys
from pathlib import Path
from types import SimpleNamespace
from typing import Any

import httpx
import pytest
import requests
from scrapling import fetchers

ROOT = Path(__file__).resolve().parent.parent
FIX = Path(__file__).resolve().parent / "fixtures"


@pytest.fixture
def fixture_text():
    def _load(name: str) -> str:
        p = FIX / name
        return p.read_text(encoding="utf-8")

    return _load


def _load_scraper_module(module_path: Path, module_name: str):
    spec = importlib.util.spec_from_file_location(
        f"scrapers.{module_name}", module_path
    )
    if spec is None or spec.loader is None:
        raise ImportError(f"Cannot load module {module_name}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[f"scrapers.{module_name}"] = module
    spec.loader.exec_module(module)
    return module


def _capture_stdout(coro):
    buf = io.StringIO()
    old = sys.stdout
    sys.stdout = buf
    try:
        rc = asyncio.run(coro)
        out = buf.getvalue()
    finally:
        sys.stdout = old
    return rc, out


@pytest.fixture
def run_scraper_offline(fixture_text):
    def _router_cses(*, path: str | None = None, url: str | None = None) -> str:
        if not path and not url:
            raise AssertionError("CSES expects path or url")

        target = path or url
        if target is None:
            raise AssertionError(f"No target for CSES (path={path!r}, url={url!r})")

        if target.startswith("https://cses.fi"):
            target = target.removeprefix("https://cses.fi")

        if target.strip("/") == "problemset":
            return fixture_text("cses_contests.html")

        if target.startswith("/problemset/task/") or target.startswith(
            "problemset/task/"
        ):
            pid = target.rstrip("/").split("/")[-1]
            return fixture_text(f"cses_task_{pid}.html")

        raise AssertionError(f"No fixture for CSES path={path!r} url={url!r}")

    def _router_atcoder(*, path: str | None = None, url: str | None = None) -> str:
        if not url:
            raise AssertionError("AtCoder expects url routing")
        if "/contests/archive" in url:
            return fixture_text("atcoder_contests.html")
        if url.endswith("/tasks"):
            return fixture_text("atcoder_abc100_tasks.html")
        if "/tasks/" in url:
            slug = url.rsplit("/", 1)[-1]
            return fixture_text(f"atcoder_task_{slug}.html")
        raise AssertionError(f"No fixture for AtCoder url={url!r}")

    def _router_codeforces(*, path: str | None = None, url: str | None = None) -> str:
        if not url:
            raise AssertionError("Codeforces expects url routing")
        if "/contest/" in url and url.endswith("/problems"):
            contest_id = url.rstrip("/").split("/")[-2]
            return fixture_text(f"codeforces_{contest_id}_problems.html")
        if "/contests" in url and "/problem/" not in url:
            return fixture_text("codeforces_contests.html")
        if "/problem/" in url:
            parts = url.rstrip("/").split("/")
            contest_id, index = parts[-3], parts[-1]
            return fixture_text(f"codeforces_{contest_id}_{index}.html")
        if "/problemset/problem/" in url:
            parts = url.rstrip("/").split("/")
            contest_id, index = parts[-2], parts[-1]
            return fixture_text(f"codeforces_{contest_id}_{index}.html")

        raise AssertionError(f"No fixture for Codeforces url={url!r}")

    def _make_offline_fetches(scraper_name: str):
        match scraper_name:
            case "cses":

                async def __offline_fetch_text(client, path: str, **kwargs):
                    html = _router_cses(path=path)
                    return SimpleNamespace(
                        text=html,
                        status_code=200,
                        raise_for_status=lambda: None,
                    )

                return {
                    "__offline_fetch_text": __offline_fetch_text,
                }

            case "atcoder":

                def __offline_fetch(url: str, *args, **kwargs):
                    html = _router_atcoder(url=url)
                    return html

                async def __offline_get_async(client, url: str, **kwargs):
                    return _router_atcoder(url=url)

                return {
                    "_fetch": __offline_fetch,
                    "_get_async": __offline_get_async,
                }

            case "codeforces":

                class MockPage:
                    def __init__(self, html: str):
                        self.html_content = html

                def _mock_stealthy_fetch(url: str, **kwargs):
                    return MockPage(_router_codeforces(url=url))

                def _mock_requests_get(url: str, **kwargs):
                    if "api/contest.list" in url:
                        data = {
                            "status": "OK",
                            "result": [
                                {
                                    "id": 1550,
                                    "name": "Educational Codeforces Round 155 (Rated for Div. 2)",
                                    "phase": "FINISHED",
                                },
                                {
                                    "id": 1000,
                                    "name": "Codeforces Round #1000",
                                    "phase": "FINISHED",
                                },
                            ],
                        }

                        class R:
                            def json(self_inner):
                                return data

                            def raise_for_status(self_inner):
                                return None

                        return R()
                    raise AssertionError(f"Unexpected requests.get call: {url}")

                return {
                    "StealthyFetcher.fetch": _mock_stealthy_fetch,
                    "requests.get": _mock_requests_get,
                }

            case _:
                raise AssertionError(f"Unknown scraper: {scraper_name}")

    def _run(scraper_name: str, mode: str, *args: str):
        mod_path = ROOT / "scrapers" / f"{scraper_name}.py"
        ns = _load_scraper_module(mod_path, scraper_name)
        offline_fetches = _make_offline_fetches(scraper_name)

        if scraper_name == "codeforces":
            fetchers.stealthyfetcher.fetch = offline_fetches["stealthyfetcher.fetch"]  # type: ignore
            requests.get = offline_fetches["requests.get"]
        elif scraper_name == "atcoder":
            ns._fetch = offline_fetches["_fetch"]
            ns._get_async = offline_fetches["_get_async"]
        elif scraper_name == "cses":
            httpx.asyncclient.get = offline_fetches["__offline_fetch_text"]  # type: ignore

        main_async = getattr(ns, "main_async")
        assert callable(main_async), f"main_async not found in {scraper_name}"

        argv = [str(mod_path), mode, *args]
        old_argv = sys.argv
        sys.argv = argv
        try:
            rc, out = _capture_stdout(main_async())
        finally:
            sys.argv = old_argv

        json_lines: list[Any] = []
        for line in (l for l in out.splitlines() if l.strip()):
            json_lines.append(json.loads(line))
        return rc, json_lines

    return _run
