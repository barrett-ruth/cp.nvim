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
        if mode == "metadata":
            assert model.success in (True, False)
            if model.success:
                assert len(model.problems) >= 1
                assert all(isinstance(p.id, str) and p.id for p in model.problems)
        else:
            assert model.success in (True, False)
            if model.success:
                assert len(model.contests) >= 1
    else:
        validated_any = False
        for obj in objs:
            if "success" in obj and "tests" in obj and "problem_id" in obj:
                tr = TestsResult.model_validate(obj)
                assert tr.problem_id != ""
                assert isinstance(tr.tests, list)
                validated_any = True
            else:
                assert "problem_id" in obj
                assert "tests" in obj and isinstance(obj["tests"], list)
                assert (
                    "timeout_ms" in obj and "memory_mb" in obj and "interactive" in obj
                )
                validated_any = True
        assert validated_any, "No valid tests payloads validated"
