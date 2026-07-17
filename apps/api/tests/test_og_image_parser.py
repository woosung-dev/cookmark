# og:image 파서 유닛 — 표준·오기·불량·잘린 HTML에서 첫 유효 content를 뽑는지 (AC: og:image 추출)
from src.ogimage.parser import extract_og_image


def test_extracts_standard_property_meta() -> None:
    html = """<html><head>
    <meta property="og:image" content="https://img.example/food.jpg">
    </head><body></body></html>"""
    assert extract_og_image(html) == "https://img.example/food.jpg"


def test_accepts_name_attribute_variant() -> None:
    """name="og:image"는 흔한 오기다 — 받아준다 (비용 0)."""
    html = '<meta name="og:image" content="https://img.example/a.jpg">'
    assert extract_og_image(html) == "https://img.example/a.jpg"


def test_attribute_order_does_not_matter() -> None:
    html = '<meta content="https://img.example/b.jpg" property="og:image">'
    assert extract_og_image(html) == "https://img.example/b.jpg"


def test_self_closing_meta() -> None:
    html = '<meta property="og:image" content="https://img.example/c.jpg" />'
    assert extract_og_image(html) == "https://img.example/c.jpg"


def test_first_occurrence_wins() -> None:
    html = (
        '<meta property="og:image" content="https://img.example/first.jpg">'
        '<meta property="og:image" content="https://img.example/second.jpg">'
    )
    assert extract_og_image(html) == "https://img.example/first.jpg"


def test_empty_content_is_skipped() -> None:
    html = (
        '<meta property="og:image" content="">'
        '<meta property="og:image" content="   ">'
        '<meta property="og:image" content="https://img.example/real.jpg">'
    )
    assert extract_og_image(html) == "https://img.example/real.jpg"


def test_content_entities_are_unescaped() -> None:
    html = '<meta property="og:image" content="https://img.example/a?b=1&amp;c=2">'
    assert extract_og_image(html) == "https://img.example/a?b=1&c=2"


def test_missing_og_image_returns_none() -> None:
    html = '<html><head><meta property="og:title" content="레시피"></head></html>'
    assert extract_og_image(html) is None


def test_meta_without_content_returns_none() -> None:
    assert extract_og_image('<meta property="og:image">') is None


def test_truncated_html_does_not_raise() -> None:
    """상한에서 잘린 HTML — 미완성 태그는 조용히 버려진다."""
    html = '<html><head><meta property="og:image" con'
    assert extract_og_image(html) is None


def test_found_before_truncation_survives() -> None:
    html = (
        '<meta property="og:image" content="https://img.example/ok.jpg">'
        "<div><p>잘린 본문 <sp"
    )
    assert extract_og_image(html) == "https://img.example/ok.jpg"


def test_malformed_html_does_not_raise() -> None:
    html = "<html><<<>><head><meta ====><meta property=og:image content=no-quotes>"
    assert extract_og_image(html) == "no-quotes"
