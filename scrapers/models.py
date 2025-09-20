from dataclasses import dataclass, field


@dataclass
class TestCase:
    input: str
    expected: str


@dataclass
class ProblemSummary:
    id: str
    name: str


@dataclass
class ContestSummary:
    id: str
    name: str
    display_name: str


@dataclass
class ScrapingResult:
    success: bool
    error: str


@dataclass
class MetadataResult(ScrapingResult):
    contest_id: str = ""
    problems: list[ProblemSummary] = field(default_factory=list)
    categories: dict[str, list[ProblemSummary]] = field(default_factory=dict)


@dataclass
class ContestListResult(ScrapingResult):
    contests: list[ContestSummary] = field(default_factory=list)


@dataclass
class TestsResult(ScrapingResult):
    problem_id: str
    url: str
    tests: list[TestCase]
    timeout_ms: int
    memory_mb: float
