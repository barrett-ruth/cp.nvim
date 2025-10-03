from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Any, Awaitable, Callable, ParamSpec, cast

from .models import ContestListResult, MetadataResult, TestsResult

P = ParamSpec("P")


@dataclass
class ScraperConfig:
    timeout_seconds: int = 30
    max_retries: int = 3
    backoff_base: float = 2.0
    rate_limit_delay: float = 1.0


class BaseScraper(ABC):
    @property
    @abstractmethod
    def platform_name(self) -> str: ...

    @abstractmethod
    async def scrape_contest_metadata(self, contest_id: str) -> MetadataResult: ...

    @abstractmethod
    async def scrape_problem_tests(
        self, contest_id: str, problem_id: str
    ) -> TestsResult: ...

    @abstractmethod
    async def scrape_contest_list(self) -> ContestListResult: ...

    @abstractmethod
    async def stream_tests_for_category_async(self, category_id: str) -> None: ...

    def _create_metadata_error(
        self, error_msg: str, contest_id: str = ""
    ) -> MetadataResult:
        return MetadataResult(
            success=False,
            error=f"{self.platform_name}: {error_msg}",
            contest_id=contest_id,
        )

    def _create_tests_error(
        self, error_msg: str, problem_id: str = "", url: str = ""
    ) -> TestsResult:
        return TestsResult(
            success=False,
            error=f"{self.platform_name}: {error_msg}",
            problem_id=problem_id,
            url=url,
            tests=[],
            timeout_ms=0,
            memory_mb=0,
        )

    def _create_contests_error(self, error_msg: str) -> ContestListResult:
        return ContestListResult(
            success=False, error=f"{self.platform_name}: {error_msg}"
        )

    async def _safe_execute(
        self,
        operation: str,
        func: Callable[P, Awaitable[Any]],
        *args: P.args,
        **kwargs: P.kwargs,
    ):
        try:
            return await func(*args, **kwargs)
        except Exception as e:
            if operation == "metadata":
                contest_id = cast(str, args[0]) if args else ""
                return self._create_metadata_error(str(e), contest_id)
            elif operation == "tests":
                problem_id = cast(str, args[1]) if len(args) > 1 else ""
                return self._create_tests_error(str(e), problem_id)
            elif operation == "contests":
                return self._create_contests_error(str(e))
            else:
                raise
