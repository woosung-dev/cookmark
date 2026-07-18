# LLM 프롬프트 정본 — 라우트·서비스 인라인 금지(backend.md §4). 원문은 루트 프록시 .mjs verbatim 이식(#101)
from collections.abc import Sequence

from src.llm.schemas import MatchRecipe

RECOGNIZE_PROMPT = "\n".join(
    [
        "이 냉장고 사진에 실제로 보이는 식재료만 한국어로 나열해 주세요.",
        "",
        "규칙:",
        "- 사진에서 보이는 것만 적습니다. 냉장고에 있을 법한 것을 추측해서 넣지 마세요.",
        "- 각 항목에 confidence를 붙입니다. high = 분명히 보임, medium = 보이지만 확실치 않음, low = 있을 수도 있음.",
        '- 용기 안이 안 보이면 추측하지 말고 보이는 그대로("반찬통", "소스류") 적고 confidence를 낮춥니다.',
        # #101 이식 조정 — 필드명이 스키마의 snake_case(low_quality)로 바뀌어 단어만 맞췄다.
        "- 사진이 너무 어둡거나 흐려서 판독이 불가능하면 low_quality를 true로 하고 ingredients를 비웁니다.",
    ]
)


def extract_prompt(title: str) -> str:
    """제목 추론 프롬프트 — URL 사다리(#123)의 최종 단이자 url 부재 시의 기존 경로."""
    return "\n".join(
        [
            f'"{title}"을(를) 만들 때 보통 들어가는 재료를 한국어로 나열해 주세요.',
            "",
            "규칙:",
            "- 재료 이름만 적습니다. 분량·조리법은 적지 마세요.",
            "- 흔한 조리법 기준으로 적습니다. 특정 레시피를 그대로 옮기려 하지 마세요.",
            "- 요리명이 무엇인지 알 수 없으면 ingredients를 빈 배열로 두세요.",
        ]
    )


# 영상 직독 프롬프트 — 스파이크(#123)에서 실증된 지시를 정본화했다. JSON 형태는 response_schema가 강제한다.
EXTRACT_VIDEO_PROMPT = "\n".join(
    [
        "이 요리 영상에서 실제로 사용된 재료만 한국어로 나열해 주세요.",
        "",
        "규칙:",
        "- 재료 이름만 적습니다. 분량·조리법은 적지 마세요.",
        "- 영상에 등장하지 않은 재료를 추측으로 넣지 마세요.",
        "- 요리 영상이 아니거나 재료를 알 수 없으면 ingredients를 빈 배열로 두세요.",
    ]
)


def extract_content_prompt(title: str, content: str) -> str:
    """본문 기반 추출 프롬프트 — 사다리(#123)에서 JSON-LD가 없을 때 페이지 텍스트로 추출한다."""
    return "\n".join(
        [
            f'다음은 "{title}" 레시피 페이지의 본문입니다. 이 요리에 들어가는 재료를 한국어로 나열해 주세요.',
            "",
            "규칙:",
            "- 재료 이름만 적습니다. 분량·조리법은 적지 마세요.",
            "- 본문에 실제로 나온 재료를 우선합니다. 본문에 없는 재료를 추측으로 넣지 마세요.",
            "- 본문이 레시피가 아니어서 재료를 알 수 없으면 ingredients를 빈 배열로 두세요.",
            "",
            "## 본문",
            content,
        ]
    )


def match_prompt(ingredients: Sequence[str], recipes: Sequence[MatchRecipe]) -> str:
    """매칭 프롬프트 — 동의어·정규화는 프롬프트 안에서 LLM이 처리한다(스펙 #13)."""
    saved_block = (
        "\n".join(
            f"- {recipe.title}: {', '.join(recipe.ingredients) or '(재료 미상)'}"
            for recipe in recipes
        )
        if recipes
        else "(저장된 레시피 없음)"
    )
    return "\n".join(
        [
            "지금 냉장고에 있는 재료로 오늘 저녁에 해먹을 메뉴를 골라 주세요.",
            "",
            "## 있는 재료",
            ", ".join(ingredients) or "(없음)",
            "",
            "## 사용자가 저장해 둔 레시피 (신뢰하는 것들)",
            saved_block,
            "",
            "## 규칙",
            '- 저장된 레시피 중에 만들 수 있는 게 있으면 **먼저** 고릅니다. source는 "saved", menu는 저장된 제목 그대로.',
            '- 저장 레시피로 3개가 안 되면 일반적인 한국 가정식으로 채웁니다. source는 "generated".',
            "- 최대 6개까지 후보를 주세요. 고르는 건 앱이 합니다.",
            "- missing에는 그 메뉴에 필요한데 없는 재료만 넣습니다. 있는 재료는 넣지 마세요.",
            '- 있는 재료로 대신할 수 있으면 substitute에 그 재료를 적습니다(예: 우유가 없고 두유가 있으면 name="우유", substitute="두유").',
            "- 대신할 게 없으면 substitute를 비웁니다.",
            # #101 이식 조정 — 매칭 % 실산출의 분모가 되는 required 규칙 1줄 추가(스펙 #96 이월 해소).
            "- required에는 그 메뉴에 필요한 재료를 전부 넣습니다. 있는 재료도 포함합니다.",
            '- 한국어 재료명의 동의어와 표기 차이는 같은 것으로 봅니다("대파"="파", "간장"="진간장", "달걀"="계란").',
            "- reason은 왜 이걸 골랐는지 한 줄로. 재료 나열 말고 사람에게 하는 말로.",
        ]
    )
