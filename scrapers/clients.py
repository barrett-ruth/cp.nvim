import time

import backoff
import requests

from .base import HttpClient, ScraperConfig


class RequestsClient:
    def __init__(self, config: ScraperConfig, headers: dict[str, str] | None = None):
        self.config = config
        self.session = requests.Session()

        default_headers = {
            "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        }
        if headers:
            default_headers.update(headers)

        self.session.headers.update(default_headers)

    @backoff.on_exception(
        backoff.expo,
        (requests.RequestException, requests.HTTPError),
        max_tries=3,
        base=2.0,
        jitter=backoff.random_jitter,
    )
    @backoff.on_predicate(
        backoff.expo,
        lambda response: response.status_code == 429,
        max_tries=3,
        base=2.0,
        jitter=backoff.random_jitter,
    )
    def get(self, url: str, **kwargs) -> requests.Response:
        timeout = kwargs.get("timeout", self.config.timeout_seconds)
        response = self.session.get(url, timeout=timeout, **kwargs)
        response.raise_for_status()

        if (
            hasattr(self.config, "rate_limit_delay")
            and self.config.rate_limit_delay > 0
        ):
            time.sleep(self.config.rate_limit_delay)

        return response

    def close(self) -> None:
        self.session.close()


class CloudScraperClient:
    def __init__(self, config: ScraperConfig):
        import cloudscraper

        self.config = config
        self.scraper = cloudscraper.create_scraper()

    @backoff.on_exception(
        backoff.expo,
        (requests.RequestException, requests.HTTPError),
        max_tries=3,
        base=2.0,
        jitter=backoff.random_jitter,
    )
    def get(self, url: str, **kwargs) -> requests.Response:
        timeout = kwargs.get("timeout", self.config.timeout_seconds)
        response = self.scraper.get(url, timeout=timeout, **kwargs)
        response.raise_for_status()

        if (
            hasattr(self.config, "rate_limit_delay")
            and self.config.rate_limit_delay > 0
        ):
            time.sleep(self.config.rate_limit_delay)

        return response

    def close(self) -> None:
        if hasattr(self.scraper, "close"):
            self.scraper.close()
