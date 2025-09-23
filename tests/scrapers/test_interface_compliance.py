import inspect
from unittest.mock import Mock

import pytest

import scrapers
from scrapers.base import BaseScraper
from scrapers.models import ContestListResult, MetadataResult, TestsResult

SCRAPERS = [
    cls
    for name, cls in inspect.getmembers(scrapers, inspect.isclass)
    if issubclass(cls, BaseScraper) and cls != BaseScraper
]


class TestScraperInterfaceCompliance:
    @pytest.mark.parametrize("scraper_class", SCRAPERS)
    def test_implements_base_interface(self, scraper_class):
        scraper = scraper_class()

        assert isinstance(scraper, BaseScraper)
        assert hasattr(scraper, "platform_name")
        assert hasattr(scraper, "scrape_contest_metadata")
        assert hasattr(scraper, "scrape_problem_tests")
        assert hasattr(scraper, "scrape_contest_list")

    @pytest.mark.parametrize("scraper_class", SCRAPERS)
    def test_platform_name_is_string(self, scraper_class):
        scraper = scraper_class()
        platform_name = scraper.platform_name

        assert isinstance(platform_name, str)
        assert len(platform_name) > 0
        assert platform_name.islower()  # Convention: lowercase platform names

    @pytest.mark.parametrize("scraper_class", SCRAPERS)
    def test_metadata_method_signature(self, scraper_class, mocker):
        scraper = scraper_class()

        # Mock the underlying HTTP calls to avoid network requests
        if scraper.platform_name == "codeforces":
            mock_scraper = Mock()
            mock_response = Mock()
            mock_response.text = "<a href='/contest/1900/problem/A'>A. Test</a>"
            mock_scraper.get.return_value = mock_response
            mocker.patch(
                "scrapers.codeforces.cloudscraper.create_scraper",
                return_value=mock_scraper,
            )

        result = scraper.scrape_contest_metadata("test_contest")

        assert isinstance(result, MetadataResult)
        assert hasattr(result, "success")
        assert hasattr(result, "error")
        assert hasattr(result, "problems")
        assert hasattr(result, "contest_id")
        assert isinstance(result.success, bool)
        assert isinstance(result.error, str)

    @pytest.mark.parametrize("scraper_class", SCRAPERS)
    def test_problem_tests_method_signature(self, scraper_class, mocker):
        scraper = scraper_class()

        if scraper.platform_name == "codeforces":
            mock_scraper = Mock()
            mock_response = Mock()
            mock_response.text = """
            <div class="time-limit">Time limit: 1 seconds</div>
            <div class="memory-limit">Memory limit: 256 megabytes</div>
            <div class="input"><pre><div class="test-example-line-1">3</div></pre></div>
            <div class="output"><pre><div class="test-example-line-1">6</div></pre></div>
            """
            mock_scraper.get.return_value = mock_response
            mocker.patch(
                "scrapers.codeforces.cloudscraper.create_scraper",
                return_value=mock_scraper,
            )

        result = scraper.scrape_problem_tests("test_contest", "A")

        assert isinstance(result, TestsResult)
        assert hasattr(result, "success")
        assert hasattr(result, "error")
        assert hasattr(result, "tests")
        assert hasattr(result, "problem_id")
        assert hasattr(result, "url")
        assert hasattr(result, "timeout_ms")
        assert hasattr(result, "memory_mb")
        assert isinstance(result.success, bool)
        assert isinstance(result.error, str)

    @pytest.mark.parametrize("scraper_class", SCRAPERS)
    def test_contest_list_method_signature(self, scraper_class, mocker):
        scraper = scraper_class()

        if scraper.platform_name == "codeforces":
            mock_scraper = Mock()
            mock_response = Mock()
            mock_response.json.return_value = {
                "status": "OK",
                "result": [{"id": 1900, "name": "Test Contest"}],
            }
            mock_scraper.get.return_value = mock_response
            mocker.patch(
                "scrapers.codeforces.cloudscraper.create_scraper",
                return_value=mock_scraper,
            )

        result = scraper.scrape_contest_list()

        assert isinstance(result, ContestListResult)
        assert hasattr(result, "success")
        assert hasattr(result, "error")
        assert hasattr(result, "contests")
        assert isinstance(result.success, bool)
        assert isinstance(result.error, str)

    @pytest.mark.parametrize("scraper_class", SCRAPERS)
    def test_error_message_format(self, scraper_class, mocker):
        scraper = scraper_class()
        platform_name = scraper.platform_name

        # Force an error by mocking HTTP failure
        if scraper.platform_name == "codeforces":
            mock_scraper = Mock()
            mock_scraper.get.side_effect = Exception("Network error")
            mocker.patch(
                "scrapers.codeforces.cloudscraper.create_scraper",
                return_value=mock_scraper,
            )
        elif scraper.platform_name == "atcoder":
            mocker.patch(
                "scrapers.atcoder.requests.get", side_effect=Exception("Network error")
            )
        elif scraper.platform_name == "cses":
            mocker.patch(
                "scrapers.cses.make_request", side_effect=Exception("Network error")
            )

        # Test metadata error format
        result = scraper.scrape_contest_metadata("test")
        assert not result.success
        assert result.error.startswith(f"{platform_name}: ")

        # Test problem tests error format
        result = scraper.scrape_problem_tests("test", "A")
        assert not result.success
        assert result.error.startswith(f"{platform_name}: ")

        # Test contest list error format
        result = scraper.scrape_contest_list()
        assert not result.success
        assert result.error.startswith(f"{platform_name}: ")

    @pytest.mark.parametrize("scraper_class", SCRAPERS)
    def test_scraper_instantiation(self, scraper_class):
        scraper1 = scraper_class()
        assert isinstance(scraper1, BaseScraper)
        assert scraper1.config is not None

        from scrapers.base import ScraperConfig

        custom_config = ScraperConfig(timeout_seconds=60)
        scraper2 = scraper_class(custom_config)
        assert isinstance(scraper2, BaseScraper)
        assert scraper2.config.timeout_seconds == 60
