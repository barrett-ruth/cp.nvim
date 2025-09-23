from .atcoder import AtCoderScraper
from .base import BaseScraper, ScraperConfig
from .codeforces import CodeforcesScraper
from .cses import CSESScraper
from .models import (
    ContestListResult,
    ContestSummary,
    MetadataResult,
    ProblemSummary,
    TestCase,
    TestsResult,
)

ALL_SCRAPERS: dict[str, type[BaseScraper]] = {
    "atcoder": AtCoderScraper,
    "codeforces": CodeforcesScraper,
    "cses": CSESScraper,
}

_SCRAPER_CLASSES = [
    "AtCoderScraper",
    "CodeforcesScraper",
    "CSESScraper",
]

_BASE_EXPORTS = [
    "BaseScraper",
    "ScraperConfig",
    "ContestListResult",
    "ContestSummary",
    "MetadataResult",
    "ProblemSummary",
    "TestCase",
    "TestsResult",
]

_REGISTRY_FUNCTIONS = [
    "get_scraper",
    "list_platforms",
    "ALL_SCRAPERS",
]

__all__ = _BASE_EXPORTS + _SCRAPER_CLASSES + _REGISTRY_FUNCTIONS


def get_scraper(platform: str) -> type[BaseScraper]:
    if platform not in ALL_SCRAPERS:
        available = ", ".join(ALL_SCRAPERS.keys())
        raise KeyError(
            f"Unknown platform '{platform}'. Available platforms: {available}"
        )
    return ALL_SCRAPERS[platform]


def list_platforms() -> list[str]:
    return list(ALL_SCRAPERS.keys())
