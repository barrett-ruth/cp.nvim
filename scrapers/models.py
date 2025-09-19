from dataclasses import dataclass


@dataclass
class TestCase:
    input: str
    expected: str


@dataclass
class Problem:
    id: str
    name: str


@dataclass
class ScrapingResult:
    success: bool
    error: str | None = None


@dataclass
class MetadataResult(ScrapingResult):
    contest_id: str | None = None
    problems: list[Problem] | None = None
    categories: dict[str, list[Problem]] | None = None

    def __post_init__(self):
        if self.problems is None:
            self.problems = []


@dataclass
class TestsResult(ScrapingResult):
    problem_id: str = ""
    url: str = ""
    tests: list[TestCase] | None = None

    def __post_init__(self):
        if self.tests is None:
            self.tests = []
