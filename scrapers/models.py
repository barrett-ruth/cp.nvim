from pydantic import BaseModel, Field


class TestCase(BaseModel):
    input: str
    expected: str

    class Config:
        extra = "forbid"


class ProblemSummary(BaseModel):
    id: str
    name: str

    class Config:
        extra = "forbid"


class ContestSummary(BaseModel):
    id: str
    name: str
    display_name: str | None = None

    class Config:
        extra = "forbid"


class ScrapingResult(BaseModel):
    success: bool
    error: str

    class Config:
        extra = "forbid"


class MetadataResult(ScrapingResult):
    contest_id: str = ""
    problems: list[ProblemSummary] = Field(default_factory=list)

    class Config:
        extra = "forbid"


class ContestListResult(ScrapingResult):
    contests: list[ContestSummary] = Field(default_factory=list)

    class Config:
        extra = "forbid"


class TestsResult(ScrapingResult):
    problem_id: str
    url: str
    tests: list[TestCase] = Field(default_factory=list)
    timeout_ms: int
    memory_mb: float
    interactive: bool = False

    class Config:
        extra = "forbid"


class ScraperConfig(BaseModel):
    timeout_seconds: int = 30
    max_retries: int = 3
    backoff_base: float = 2.0
    rate_limit_delay: float = 1.0

    class Config:
        extra = "forbid"
