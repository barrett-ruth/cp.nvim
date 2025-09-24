# Lazy imports to avoid module loading conflicts when running scrapers with -m
def __getattr__(name):
    if name == "AtCoderScraper":
        from .atcoder import AtCoderScraper

        return AtCoderScraper
    elif name == "BaseScraper":
        from .base import BaseScraper

        return BaseScraper
    elif name == "ScraperConfig":
        from .base import ScraperConfig

        return ScraperConfig
    elif name == "CodeforcesScraper":
        from .codeforces import CodeforcesScraper

        return CodeforcesScraper
    elif name == "CSESScraper":
        from .cses import CSESScraper

        return CSESScraper
    elif name in [
        "ContestListResult",
        "ContestSummary",
        "MetadataResult",
        "ProblemSummary",
        "TestCase",
        "TestsResult",
    ]:
        from .models import (
            ContestListResult,
            ContestSummary,
            MetadataResult,
            ProblemSummary,
            TestCase,
            TestsResult,
        )

        return locals()[name]
    raise AttributeError(f"module 'scrapers' has no attribute '{name}'")


__all__ = [
    "AtCoderScraper",
    "BaseScraper",
    "CodeforcesScraper",
    "CSESScraper",
    "ScraperConfig",
    "ContestListResult",
    "ContestSummary",
    "MetadataResult",
    "ProblemSummary",
    "TestCase",
    "TestsResult",
]
