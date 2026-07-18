# 추출 사다리 결정적 단 유닛 — 유튜브 판별·JSON-LD Recipe 파싱·본문 텍스트 상한 (#123)
import json

import pytest

from src.llm import ingest

# ── classify — 유튜브 판별 ───────────────────────────────────────────────────


@pytest.mark.parametrize(
    "url",
    [
        "https://youtube.com/watch?v=tDlw8yMg9NY",
        "https://www.youtube.com/watch?v=tDlw8yMg9NY",
        "https://m.youtube.com/watch?v=tDlw8yMg9NY",
        "https://youtu.be/tDlw8yMg9NY",
        "https://www.youtube.com/shorts/abc123",
        "http://youtu.be/tDlw8yMg9NY",
        "https://WWW.YOUTUBE.COM/watch?v=x",  # 호스트는 대소문자 무시
    ],
)
def test_youtube_variants_are_youtube(url: str) -> None:
    assert ingest.classify(url) == "youtube"


@pytest.mark.parametrize(
    "url",
    [
        "https://blog.naver.com/recipe/123",
        "https://vimeo.com/123",
        "https://youtube.com.evil.example/watch",  # 서픽스 위장 — 정확 일치만 유튜브다
        "https://youtu.be@evil.com/watch",  # userinfo 위장 — hostname은 evil.com이라 web(→urlguard 거부)
        "https://notyoutu.be/x",
        "ftp://youtu.be/x",  # 허용 스킴 아님 — 영상 단으로 보내지 않는다
        "https:///watch",
    ],
)
def test_non_youtube_is_web(url: str) -> None:
    assert ingest.classify(url) == "web"


@pytest.mark.parametrize(
    "url",
    [
        "http://[::1",  # 괄호 불균형 IPv6 — urlsplit ValueError
        "http://exa[mple.com/recipe",  # '[' 포함 오타
    ],
)
def test_unparseable_url_is_invalid(url: str) -> None:
    """R2: 파싱 불가 URL은 예외가 아니라 "invalid" — 호출자가 fetch 없이 제목 단으로 보낸다."""
    assert ingest.classify(url) == "invalid"


# ── strip_userinfo — 자격증명이 Gemini(file_uri)로 새지 않게 ────────────────


def test_strip_userinfo_removes_credentials() -> None:
    assert (
        ingest.strip_userinfo("https://user:secret@youtu.be/tDlw8yMg9NY")
        == "https://youtu.be/tDlw8yMg9NY"
    )


def test_strip_userinfo_keeps_path_query_fragment_and_port() -> None:
    assert (
        ingest.strip_userinfo("https://user:pass@youtube.com:8443/watch?v=x&t=10#top")
        == "https://youtube.com:8443/watch?v=x&t=10#top"
    )


@pytest.mark.parametrize(
    "url",
    [
        "https://youtu.be/tDlw8yMg9NY",
        "https://www.youtube.com/watch?v=x&t=10",
    ],
)
def test_strip_userinfo_leaves_normal_url_unchanged(url: str) -> None:
    assert ingest.strip_userinfo(url) == url


@pytest.mark.parametrize(
    "url",
    [
        "http://[::1",  # 괄호 불균형 IPv6 — urlsplit ValueError
        "http://u:p@youtu.be:99999999/x",  # 범위초과 포트 — .port ValueError
    ],
)
def test_strip_userinfo_unparseable_returns_original(url: str) -> None:
    """파싱 불가는 원본 반환 — classify가 유효 host를 보장하므로 유튜브 단에는 도달하지 않는다."""
    assert ingest.strip_userinfo(url) == url


# ── fetch_page — 광범위 강등 변환 ───────────────────────────────────────────


async def test_fetch_page_범위초과_포트는_IngestFetchError() -> None:
    """R: anyio가 OverflowError를 ExceptionGroup으로 감싸 던진다(httpx.HTTPError 아님) —
    좁은 목록이 아니라 광범위 변환이라 IngestFetchError 하나로 나온다. 포트가 불법이라
    connect 이전에 실패하므로 실 네트워크가 없다."""
    with pytest.raises(ingest.IngestFetchError):
        await ingest.fetch_page("http://93.184.216.34:99999999/recipe")


# ── parse_jsonld_recipe ─────────────────────────────────────────────────────


def script(payload: object) -> str:
    return (
        '<html><head><script type="application/ld+json">'
        f"{json.dumps(payload, ensure_ascii=False)}"
        "</script></head><body>본문</body></html>"
    )


def test_plain_recipe_block() -> None:
    html = script({"@type": "Recipe", "recipeIngredient": ["김치 300g", "두부 1모"]})
    assert ingest.parse_jsonld_recipe(html) == ["김치 300g", "두부 1모"]


def test_recipe_inside_graph() -> None:
    html = script(
        {
            "@context": "https://schema.org",
            "@graph": [
                {"@type": "WebPage", "name": "레시피 페이지"},
                {"@type": "Recipe", "recipeIngredient": ["오징어", "양파"]},
            ],
        }
    )
    assert ingest.parse_jsonld_recipe(html) == ["오징어", "양파"]


def test_list_type_recipe() -> None:
    html = script(
        {"@type": ["Recipe", "NewsArticle"], "recipeIngredient": ["달걀", "대파"]}
    )
    assert ingest.parse_jsonld_recipe(html) == ["달걀", "대파"]


def test_top_level_list_of_nodes() -> None:
    html = script(
        [
            {"@type": "BreadcrumbList"},
            {"@type": "Recipe", "recipeIngredient": ["돼지고기"]},
        ]
    )
    assert ingest.parse_jsonld_recipe(html) == ["돼지고기"]


def test_empty_recipe_ingredient_is_none() -> None:
    """recipeIngredient가 빈 배열이면 이 단은 실패다 — 다음 단(본문)으로 강등돼야 한다."""
    html = script({"@type": "Recipe", "recipeIngredient": []})
    assert ingest.parse_jsonld_recipe(html) is None


def test_no_recipe_node_is_none() -> None:
    html = script({"@type": "NewsArticle", "articleBody": "뉴스"})
    assert ingest.parse_jsonld_recipe(html) is None


def test_broken_json_block_is_skipped_not_raised() -> None:
    html = '<script type="application/ld+json">{깨진 json</script>' + script(
        {"@type": "Recipe", "recipeIngredient": ["멸치"]}
    )
    assert ingest.parse_jsonld_recipe(html) == ["멸치"]


def test_blank_and_non_string_items_are_dropped() -> None:
    html = script(
        {"@type": "Recipe", "recipeIngredient": ["  당근  ", "", 3, {"name": "x"}]}
    )
    assert ingest.parse_jsonld_recipe(html) == ["당근"]


def test_no_jsonld_script_is_none() -> None:
    assert ingest.parse_jsonld_recipe("<html><body>그냥 글</body></html>") is None


def test_ingredient_count_is_capped() -> None:
    """R4: 악의적 페이지의 수만 개 재료가 DB·응답에 그대로 실리면 안 된다 — 개수 상한."""
    raw = [f"재료{i}" for i in range(ingest.MAX_JSONLD_INGREDIENTS + 5)]
    html = script({"@type": "Recipe", "recipeIngredient": raw})
    assert ingest.parse_jsonld_recipe(html) == raw[: ingest.MAX_JSONLD_INGREDIENTS]


def test_ingredient_length_is_capped() -> None:
    """R4: 초장문 재료 문자열은 trim 후 길이 상한까지 잘린다 — 정상 길이는 그대로."""
    long_item = "가" * (ingest.MAX_JSONLD_INGREDIENT_CHARS * 3)
    html = script(
        {"@type": "Recipe", "recipeIngredient": [f"  {long_item}  ", "두부 1모"]}
    )
    assert ingest.parse_jsonld_recipe(html) == [
        long_item[: ingest.MAX_JSONLD_INGREDIENT_CHARS],
        "두부 1모",
    ]


# ── html_to_text ────────────────────────────────────────────────────────────


def test_tags_removed_and_whitespace_collapsed() -> None:
    html = "<html><body><h1>김치찌개</h1>\n\n  <p>재료는   <b>김치</b>다.</p></body></html>"
    # 인라인 태그(<b>)는 단어를 쪼개지 않는다 — 블록 사이 개행·연속 공백만 하나로 축약된다.
    assert ingest.html_to_text(html) == "김치찌개 재료는 김치다."


def test_script_and_style_contents_are_dropped() -> None:
    html = "<style>.a{color:red}</style><script>var x=1;</script><p>본문만 남는다</p>"
    assert ingest.html_to_text(html) == "본문만 남는다"


def test_text_is_capped_at_limit() -> None:
    html = "<p>" + "가" * (ingest.TEXT_LIMIT * 2) + "</p>"
    text = ingest.html_to_text(html)
    assert len(text) == ingest.TEXT_LIMIT
