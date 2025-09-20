from unittest.mock import Mock

from scrapers.cses import (
    denormalize_category_name,
    normalize_category_name,
    scrape,
    scrape_all_problems,
    scrape_categories,
    scrape_category_problems,
)
from scrapers.models import ContestSummary, ProblemSummary


def test_scrape_success(mocker, mock_cses_html):
    mock_response = Mock()
    mock_response.text = mock_cses_html

    mocker.patch("scrapers.cses.requests.get", return_value=mock_response)

    result = scrape("https://cses.fi/problemset/task/1068")

    assert len(result) == 1
    assert result[0].input == "3\n1 2 3"
    assert result[0].expected == "6"


def test_scrape_all_problems(mocker):
    mock_response = Mock()
    mock_response.text = """
    <div class="content">
        <h1>Introductory Problems</h1>
        <ul>
            <li><a href="/problemset/task/1068">Weird Algorithm</a></li>
            <li><a href="/problemset/task/1083">Missing Number</a></li>
        </ul>
        <h1>Sorting and Searching</h1>
        <ul>
            <li><a href="/problemset/task/1084">Apartments</a></li>
        </ul>
    </div>
    """
    mock_response.raise_for_status = Mock()

    mocker.patch("scrapers.cses.requests.get", return_value=mock_response)

    result = scrape_all_problems()

    assert "Introductory Problems" in result
    assert "Sorting and Searching" in result
    assert len(result["Introductory Problems"]) == 2
    assert result["Introductory Problems"][0] == ProblemSummary(
        id="1068",
        name="Weird Algorithm",
    )


def test_scrape_network_error(mocker):
    mocker.patch("scrapers.cses.requests.get", side_effect=Exception("Network error"))

    result = scrape("https://cses.fi/problemset/task/1068")

    assert result == []


def test_normalize_category_name():
    assert normalize_category_name("Sorting and Searching") == "sorting_and_searching"
    assert normalize_category_name("Dynamic Programming") == "dynamic_programming"
    assert normalize_category_name("Graph Algorithms") == "graph_algorithms"


def test_denormalize_category_name():
    assert denormalize_category_name("sorting_and_searching") == "Sorting and Searching"
    assert denormalize_category_name("dynamic_programming") == "Dynamic Programming"
    assert denormalize_category_name("graph_algorithms") == "Graph Algorithms"


def test_scrape_category_problems_success(mocker):
    mock_response = Mock()
    mock_response.text = """
    <div class="content">
        <h1>General</h1>
        <ul>
            <li><a href="/problemset/task/1000">Test Problem</a></li>
        </ul>
        <h1>Sorting and Searching</h1>
        <ul>
            <li><a href="/problemset/task/1640">Sum of Two Values</a></li>
            <li><a href="/problemset/task/1643">Maximum Subarray Sum</a></li>
        </ul>
        <h1>Dynamic Programming</h1>
        <ul>
            <li><a href="/problemset/task/1633">Dice Combinations</a></li>
        </ul>
    </div>
    """
    mock_response.raise_for_status = Mock()

    mocker.patch("scrapers.cses.requests.get", return_value=mock_response)

    result = scrape_category_problems("sorting_and_searching")

    assert len(result) == 2
    assert result[0].id == "1640"
    assert result[0].name == "Sum of Two Values"
    assert result[1].id == "1643"
    assert result[1].name == "Maximum Subarray Sum"


def test_scrape_category_problems_not_found(mocker):
    mock_response = Mock()
    mock_response.text = """
    <div class="content">
        <h1>Some Other Category</h1>
        <ul>
            <li><a href="/problemset/task/1000">Test Problem</a></li>
        </ul>
    </div>
    """
    mock_response.raise_for_status = Mock()

    mocker.patch("scrapers.cses.requests.get", return_value=mock_response)

    result = scrape_category_problems("nonexistent_category")

    assert result == []


def test_scrape_category_problems_network_error(mocker):
    mocker.patch("scrapers.cses.requests.get", side_effect=Exception("Network error"))

    result = scrape_category_problems("sorting_and_searching")

    assert result == []


def test_scrape_categories_success(mocker):
    mock_response = Mock()
    mock_response.text = """
    <html>
        <body>
            <h2>General</h2>
            <ul class="task-list">
                <li class="link"><a href="/register">Register</a></li>
            </ul>

            <h2>Introductory Problems</h2>
            <ul class="task-list">
                <li class="task"><a href="/problemset/task/1068">Weird Algorithm</a></li>
                <li class="task"><a href="/problemset/task/1083">Missing Number</a></li>
            </ul>

            <h2>Sorting and Searching</h2>
            <ul class="task-list">
                <li class="task"><a href="/problemset/task/1621">Distinct Numbers</a></li>
                <li class="task"><a href="/problemset/task/1084">Apartments</a></li>
                <li class="task"><a href="/problemset/task/1090">Ferris Wheel</a></li>
            </ul>
        </body>
    </html>
    """
    mock_response.raise_for_status = Mock()

    mocker.patch("scrapers.cses.requests.get", return_value=mock_response)

    result = scrape_categories()

    assert len(result) == 2
    assert result[0] == ContestSummary(
        id="introductory_problems",
        name="Introductory Problems",
        display_name="Introductory Problems (2 problems)",
    )
    assert result[1] == ContestSummary(
        id="sorting_and_searching",
        name="Sorting and Searching",
        display_name="Sorting and Searching (3 problems)",
    )


def test_scrape_categories_network_error(mocker):
    mocker.patch("scrapers.cses.requests.get", side_effect=Exception("Network error"))

    result = scrape_categories()

    assert result == []
