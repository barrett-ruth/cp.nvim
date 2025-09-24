from unittest.mock import Mock

from scrapers.atcoder import scrape, scrape_contest_problems, scrape_contests
from scrapers.models import ContestSummary, ProblemSummary


def test_scrape_success(mocker, mock_atcoder_html):
    mock_response = Mock()
    mock_response.text = mock_atcoder_html

    mocker.patch("scrapers.atcoder.requests.get", return_value=mock_response)

    result = scrape("https://atcoder.jp/contests/abc350/tasks/abc350_a")

    assert len(result) == 1
    assert result[0].input == "3\n1 2 3"
    assert result[0].expected == "6"


def test_scrape_contest_problems(mocker):
    mock_response = Mock()
    mock_response.text = """
    <table class="table">
        <tr><th>Task</th><th>Name</th></tr>
        <tr>
            <td></td>
            <td><a href="/contests/abc350/tasks/abc350_a">A - Water Tank</a></td>
        </tr>
        <tr>
            <td></td>
            <td><a href="/contests/abc350/tasks/abc350_b">B - Dentist Aoki</a></td>
        </tr>
    </table>
    """

    mocker.patch("scrapers.atcoder.requests.get", return_value=mock_response)

    result = scrape_contest_problems("abc350")

    assert len(result) == 2
    assert result[0] == ProblemSummary(id="a", name="A - Water Tank")
    assert result[1] == ProblemSummary(id="b", name="B - Dentist Aoki")


def test_scrape_network_error(mocker):
    mocker.patch(
        "scrapers.atcoder.requests.get", side_effect=Exception("Network error")
    )

    result = scrape("https://atcoder.jp/contests/abc350/tasks/abc350_a")

    assert result == []


def test_scrape_contests_success(mocker):
    def mock_get_side_effect(url, **kwargs):
        if url == "https://atcoder.jp/contests/archive":
            mock_response = Mock()
            mock_response.raise_for_status.return_value = None
            mock_response.text = """
            <html>
                <ul class="pagination">
                    <li>1</li>
                </ul>
            </html>
            """
            return mock_response
        elif "page=1" in url:
            mock_response = Mock()
            mock_response.raise_for_status.return_value = None
            mock_response.text = """
            <table class="table">
                <tbody>
                    <tr>
                        <td>2025-01-15 21:00:00+0900</td>
                        <td><a href="/contests/abc350">AtCoder Beginner Contest 350</a></td>
                        <td>01:40</td>
                        <td> - 1999</td>
                    </tr>
                    <tr>
                        <td>2025-01-14 21:00:00+0900</td>
                        <td><a href="/contests/arc170">AtCoder Regular Contest 170</a></td>
                        <td>02:00</td>
                        <td>1000 - 2799</td>
                    </tr>
                </tbody>
            </table>
            """
            return mock_response
        else:
            mock_response = Mock()
            mock_response.raise_for_status.return_value = None
            mock_response.text = "<html></html>"
            return mock_response

    mocker.patch("scrapers.atcoder.requests.get", side_effect=mock_get_side_effect)

    result = scrape_contests()

    assert len(result) == 2
    assert result[0] == ContestSummary(
        id="abc350",
        name="AtCoder Beginner Contest 350",
        display_name="AtCoder Beginner Contest 350",
    )
    assert result[1] == ContestSummary(
        id="arc170",
        name="AtCoder Regular Contest 170",
        display_name="AtCoder Regular Contest 170",
    )


def test_scrape_contests_no_table(mocker):
    mock_response = Mock()
    mock_response.text = "<html><body>No table found</body></html>"

    mocker.patch("scrapers.atcoder.requests.get", return_value=mock_response)

    result = scrape_contests()

    assert result == []


def test_scrape_contests_network_error(mocker):
    mocker.patch(
        "scrapers.atcoder.requests.get", side_effect=Exception("Network error")
    )

    result = scrape_contests()

    assert result == []


def test_scrape_contests_filters_ahc(mocker):
    def mock_get_side_effect(url, **kwargs):
        if url == "https://atcoder.jp/contests/archive":
            mock_response = Mock()
            mock_response.raise_for_status.return_value = None
            mock_response.text = """
            <html>
                <ul class="pagination">
                    <li>1</li>
                </ul>
            </html>
            """
            return mock_response
        elif "page=1" in url:
            mock_response = Mock()
            mock_response.raise_for_status.return_value = None
            mock_response.text = """
            <table class="table">
                <tbody>
                    <tr>
                        <td>2025-01-15 21:00:00+0900</td>
                        <td><a href="/contests/abc350">AtCoder Beginner Contest 350</a></td>
                        <td>01:40</td>
                        <td> - 1999</td>
                    </tr>
                    <tr>
                        <td>2025-01-14 21:00:00+0900</td>
                        <td><a href="/contests/ahc044">AtCoder Heuristic Contest 044</a></td>
                        <td>05:00</td>
                        <td>-</td>
                    </tr>
                    <tr>
                        <td>2025-01-13 21:00:00+0900</td>
                        <td><a href="/contests/arc170">AtCoder Regular Contest 170</a></td>
                        <td>02:00</td>
                        <td>1000 - 2799</td>
                    </tr>
                </tbody>
            </table>
            """
            return mock_response
        else:
            mock_response = Mock()
            mock_response.raise_for_status.return_value = None
            mock_response.text = "<html></html>"
            return mock_response

    mocker.patch("scrapers.atcoder.requests.get", side_effect=mock_get_side_effect)

    result = scrape_contests()

    assert len(result) == 2
    assert result[0] == ContestSummary(
        id="abc350",
        name="AtCoder Beginner Contest 350",
        display_name="AtCoder Beginner Contest 350",
    )
    assert result[1] == ContestSummary(
        id="arc170",
        name="AtCoder Regular Contest 170",
        display_name="AtCoder Regular Contest 170",
    )

    # Ensure ahc044 is filtered out
    contest_ids = [contest.id for contest in result]
    assert "ahc044" not in contest_ids
