import pytest

from scrapers import ALL_SCRAPERS, get_scraper, list_platforms
from scrapers.base import BaseScraper
from scrapers.codeforces import CodeforcesScraper


class TestScraperRegistry:
    def test_get_scraper_valid_platform(self):
        scraper_class = get_scraper("codeforces")
        assert scraper_class == CodeforcesScraper
        assert issubclass(scraper_class, BaseScraper)

        scraper = scraper_class()
        assert isinstance(scraper, BaseScraper)
        assert scraper.platform_name == "codeforces"

    def test_get_scraper_invalid_platform(self):
        with pytest.raises(KeyError) as exc_info:
            get_scraper("nonexistent")

        error_msg = str(exc_info.value)
        assert "nonexistent" in error_msg
        assert "Available platforms" in error_msg

    def test_list_platforms(self):
        platforms = list_platforms()

        assert isinstance(platforms, list)
        assert len(platforms) > 0
        assert "codeforces" in platforms

        assert set(platforms) == set(ALL_SCRAPERS.keys())

    def test_all_scrapers_registry(self):
        assert isinstance(ALL_SCRAPERS, dict)
        assert len(ALL_SCRAPERS) > 0

        for platform_name, scraper_class in ALL_SCRAPERS.items():
            assert isinstance(platform_name, str)
            assert platform_name.islower()

            assert issubclass(scraper_class, BaseScraper)

            scraper = scraper_class()
            assert scraper.platform_name == platform_name

    def test_registry_import_consistency(self):
        from scrapers.codeforces import CodeforcesScraper as DirectImport

        registry_class = get_scraper("codeforces")
        assert registry_class == DirectImport

    def test_all_scrapers_can_be_instantiated(self):
        for platform_name, scraper_class in ALL_SCRAPERS.items():
            scraper = scraper_class()
            assert isinstance(scraper, BaseScraper)
            assert scraper.platform_name == platform_name
