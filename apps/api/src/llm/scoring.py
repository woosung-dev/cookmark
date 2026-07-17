# 매칭 점수 산식 — 순수 함수. 앱·SDK 없이 유닛으로 검증된다 (스펙 #96 "매칭 % 산식은 순수 로직")
from collections.abc import Sequence

from src.llm.schemas import MatchResponse, MissingIngredient, Suggestion
from src.llm.service import MatchOutcome


def compute_match_score(
    required: Sequence[str], missing: Sequence[MissingIngredient]
) -> int:
    """필요 재료 대비 해소 안 된 부족의 비율 — floor(100×(필요−미해소)/필요).

    substitute가 있으면 해소로 본다(감점 없음 — 라벨 maybe의 "가능" 의미와 일치).
    floor인 이유 — 반올림은 과대평가 방향으로 튈 수 있고, 정수 나눗셈이 결정적이다.
    """
    unresolved = sum(1 for item in missing if not item.substitute)
    if not required:
        # LLM이 필요 목록을 안 준 비정상 — 부족도 없으면 공허하게 100, 있으면 보수적으로 0.
        return 100 if unresolved == 0 else 0
    return max(0, min(100, (100 * (len(required) - unresolved)) // len(required)))


def build_match_response(outcome: MatchOutcome) -> MatchResponse:
    """후보마다 점수를 붙여 wire 응답으로 조립한다 — required는 여기서 소비되고 버려진다."""
    return MatchResponse(
        suggestions=[
            Suggestion(
                menu=candidate.menu,
                source=candidate.source,
                missing=candidate.missing,
                reason=candidate.reason,
                match_score=compute_match_score(candidate.required, candidate.missing),
            )
            for candidate in outcome.candidates
        ],
        usage=outcome.usage,
    )
