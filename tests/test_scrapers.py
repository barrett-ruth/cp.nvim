import pytest

from scrapers.models import (
    ContestListResult,
    MetadataResult,
    TestsResult,
)

MODEL_FOR_MODE = {
    "metadata": MetadataResult,
    "contests": ContestListResult,
}

MATRIX = {
    "cses": {
        "metadata": ("introductory_problems",),
        "tests": ("introductory_problems",),
        "contests": tuple(),
    },
    "atcoder": {
        "metadata": ("abc100",),
        "tests": ("abc100",),
        "contests": tuple(),
    },
    "codeforces": {
        "metadata": ("1550",),
        "tests": ("1550",),
        "contests": tuple(),
    },
    "codechef": {
        "metadata": ("START209D",),
        "tests": ("START209D",),
        "contests": tuple(),
    },
}


@pytest.mark.parametrize("scraper", MATRIX.keys())
@pytest.mark.parametrize("mode", ["metadata", "tests", "contests"])
def test_scraper_offline_fixture_matrix(run_scraper_offline, scraper, mode):
    args = MATRIX[scraper][mode]
    rc, objs = run_scraper_offline(scraper, mode, *args)
    assert rc in (0, 1), f"Bad exit code {rc}"
    assert objs, f"No JSON output for {scraper}:{mode}"

    if mode in ("metadata", "contests"):
        Model = MODEL_FOR_MODE[mode]
        model = Model.model_validate(objs[-1])
        assert model is not None
        assert model.success is True
        if mode == "metadata":
            assert model.url
            assert len(model.problems) >= 1
            assert all(isinstance(p.id, str) and p.id for p in model.problems)
        else:
            assert len(model.contests) >= 1
    else:
        assert len(objs) >= 1, "No test objects returned"
        validated_any = False
        for obj in objs:
            assert "problem_id" in obj, "Missing problem_id"
            assert obj["problem_id"] != "", "Empty problem_id"
            assert "combined" in obj, "Missing combined field"
            assert isinstance(obj["combined"], dict), "combined must be a dict"
            assert "input" in obj["combined"], "Missing combined.input"
            assert "expected" in obj["combined"], "Missing combined.expected"
            assert "tests" in obj, "Missing tests field"
            assert isinstance(obj["tests"], list), "tests must be a list"
            assert "timeout_ms" in obj, "Missing timeout_ms"
            assert "memory_mb" in obj, "Missing memory_mb"
            assert "interactive" in obj, "Missing interactive"
            assert "multi_test" in obj, "Missing multi_test field"
            assert isinstance(obj["multi_test"], bool), "multi_test must be bool"
            validated_any = True
        assert validated_any, "No valid tests payloads validated"
