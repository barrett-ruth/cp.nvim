import asyncio
import sys
from abc import ABC, abstractmethod

from .models import CombinedTest, ContestListResult, MetadataResult, TestsResult


class BaseScraper(ABC):
    @property
    @abstractmethod
    def platform_name(self) -> str: ...

    @abstractmethod
    async def scrape_contest_metadata(self, contest_id: str) -> MetadataResult: ...

    @abstractmethod
    async def scrape_contest_list(self) -> ContestListResult: ...

    @abstractmethod
    async def stream_tests_for_category_async(self, category_id: str) -> None: ...

    def _usage(self) -> str:
        name = self.platform_name
        return f"Usage: {name}.py metadata <id> | tests <id> | contests"

    def _metadata_error(self, msg: str) -> MetadataResult:
        return MetadataResult(success=False, error=msg, url="")

    def _tests_error(self, msg: str) -> TestsResult:
        return TestsResult(
            success=False,
            error=msg,
            problem_id="",
            combined=CombinedTest(input="", expected=""),
            tests=[],
            timeout_ms=0,
            memory_mb=0,
        )

    def _contests_error(self, msg: str) -> ContestListResult:
        return ContestListResult(success=False, error=msg)

    async def _run_cli_async(self, args: list[str]) -> int:
        if len(args) < 2:
            print(self._metadata_error(self._usage()).model_dump_json())
            return 1

        mode = args[1]

        match mode:
            case "metadata":
                if len(args) != 3:
                    print(self._metadata_error(self._usage()).model_dump_json())
                    return 1
                result = await self.scrape_contest_metadata(args[2])
                print(result.model_dump_json())
                return 0 if result.success else 1

            case "tests":
                if len(args) != 3:
                    print(self._tests_error(self._usage()).model_dump_json())
                    return 1
                await self.stream_tests_for_category_async(args[2])
                return 0

            case "contests":
                if len(args) != 2:
                    print(self._contests_error(self._usage()).model_dump_json())
                    return 1
                result = await self.scrape_contest_list()
                print(result.model_dump_json())
                return 0 if result.success else 1

            case _:
                print(
                    self._metadata_error(
                        f"Unknown mode: {mode}. {self._usage()}"
                    ).model_dump_json()
                )
                return 1

    def run_cli(self) -> None:
        sys.exit(asyncio.run(self._run_cli_async(sys.argv)))
