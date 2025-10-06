import importlib.util
import io
import json
import sys
from pathlib import Path
from types import ModuleType

import pytest

ROOT = Path(__file__).resolve().parent.parent
FIX = Path(__file__).resolve().parent / "fixtures"


@pytest.fixture
def fixture_text():
    def _load(name: str) -> str:
        p = FIX / name
        return p.read_text(encoding="utf-8")

    return _load


def _load_scraper_module(module_path: Path, module_name: str) -> ModuleType:
    spec = importlib.util.spec_from_file_location(
        f"scrapers.{module_name}", module_path
    )
    if spec is None or spec.loader is None:
        raise ImportError(f"Could not load spec for {module_name} from {module_path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[f"scrapers.{module_name}"] = module
    spec.loader.exec_module(module)
    return module


def _capture_stdout(coro):
    import asyncio

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
        if path == "/problemset/list":
            return fixture_text("cses_contests.html")
        if path and path.startswith("/problemset/task/"):
            pid = path.rsplit("/", 1)[-1]
            return fixture_text(f"cses_task_{pid}.html")
        raise AssertionError(f"No fixture for CSES path={path!r}")

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
        if scraper_name == "cses":

            def __offline_fetch_text(client, path: str) -> str:
                return _router_cses(path=path)

            return {
                "__offline_fetch_text": __offline_fetch_text,
                "__offline_fetch_sync": lambda url: (_ for _ in ()).throw(
                    AssertionError("CSES doesn't use _fetch")
                ),
                "__offline_fetch_async": lambda client, url: (_ for _ in ()).throw(
                    AssertionError("CSES doesn't use _get_async")
                ),
            }
        if scraper_name == "atcoder":

            async def __offline_fetch_async(client, url: str) -> str:
                return _router_atcoder(url=url)

            def __offline_fetch_sync(url: str) -> str:
                return _router_atcoder(url=url)

            return {
                "__offline_fetch_text": lambda client, path: (_ for _ in ()).throw(
                    AssertionError("AtCoder doesn't use fetch_text")
                ),
                "__offline_fetch_sync": __offline_fetch_sync,
                "__offline_fetch_async": __offline_fetch_async,
            }
        if scraper_name == "codeforces":

            def __offline_fetch_sync(url: str) -> str:
                return _router_codeforces(url=url)

            return {
                "__offline_fetch_text": lambda client, path: (_ for _ in ()).throw(
                    AssertionError("Codeforces doesn't use fetch_text")
                ),
                "__offline_fetch_sync": __offline_fetch_sync,
                "__offline_fetch_async": lambda client, url: (_ for _ in ()).throw(
                    AssertionError("Codeforces doesn't use _get_async")
                ),
            }
        raise AssertionError(f"Unknown scraper: {scraper_name}")

    def _run(scraper_name: str, mode: str, *args: str):
        mod_path = ROOT / "scrapers" / f"{scraper_name}.py"
        ns = _load_scraper_module(mod_path, scraper_name)
        main_async = getattr(ns, "main_async", None)
        assert callable(main_async), f"main_async not found in {scraper_name}"

        argv = [str(mod_path), mode, *args]
        old_argv = sys.argv
        sys.argv = argv
        try:
            rc, out = _capture_stdout(main_async())
        finally:
            sys.argv = old_argv

        json_lines = []
        for line in (l for l in out.splitlines() if l.strip()):
            try:
                json_lines.append(json.loads(line))
            except json.JSONDecodeError as e:
                raise AssertionError(
                    f"Invalid JSON from {scraper_name} {mode}: {line}"
                ) from e
        return rc, json_lines

    return _run
