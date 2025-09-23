from abc import ABC, abstractmethod
from dataclasses import dataclass

from .models import ContestListResult, MetadataResult, TestsResult


@dataclass
class ScraperConfig:
    timeout_seconds: int = 30
    max_retries: int = 3
    backoff_base: float = 2.0
    rate_limit_delay: float = 1.0


class BaseScraper(ABC):
    def __init__(self, config: ScraperConfig | None = None):
        self.config = config or ScraperConfig()

    @property
    @abstractmethod
    def platform_name(self) -> str: ...

    @abstractmethod
    def scrape_contest_metadata(self, contest_id: str) -> MetadataResult: ...

    @abstractmethod
    def scrape_problem_tests(self, contest_id: str, problem_id: str) -> TestsResult: ...

    @abstractmethod
    def scrape_contest_list(self) -> ContestListResult: ...

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

    def _safe_execute(self, operation: str, func, *args, **kwargs):
        try:
            return func(*args, **kwargs)
        except Exception as e:
            if operation == "metadata":
                contest_id = args[0] if args else ""
                return self._create_metadata_error(str(e), contest_id)
            elif operation == "tests":
                problem_id = args[1] if len(args) > 1 else ""
                return self._create_tests_error(str(e), problem_id)
            elif operation == "contests":
                return self._create_contests_error(str(e))
            else:
                raise
