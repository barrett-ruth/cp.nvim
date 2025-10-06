import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent
FIXTURES = Path(__file__).resolve().parent / "fixtures"


@pytest.fixture
def fixture_text():
    """Load HTML fixture by filename."""

    def _load(name: str) -> str:
        p = FIXTURES / name
        return p.read_text(encoding="utf-8")

    return _load


@pytest.fixture
def run_scraper(monkeypatch):
    def _run(name: str, mode: str, *args, replace_fetch=None) -> dict:
        scraper_path = ROOT / "scrapers" / f"{name}.py"
        ns = {}
        code = scraper_path.read_text(encoding="utf-8")
        if replace_fetch:
            code = code.replace("def _fetch", "def _fixture_fetch")
            code += f"\n_fetch = _fixture_fetch\nfetch_text = _fixture_fetch\n"
            ns.update(replace_fetch)
        exec(compile(code, str(scraper_path), "exec"), ns)
        main_async = ns.get("main_async")
        if not main_async:
            raise RuntimeError(f"Could not load main_async from {name}.py")
        import asyncio

        async def wrapper():
            sys.argv = [str(scraper_path), mode, *args]
            return await main_async()

        return asyncio.run(wrapper())

    return _run
