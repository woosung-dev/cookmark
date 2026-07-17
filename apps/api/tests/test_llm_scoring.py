# 매칭 점수 산식 유닛 — 순수 함수라 컨테이너·앱 없이 돈다 (스펙 #96 "매칭 % 산식은 순수 로직")
from src.llm.schemas import LLMUsage, MissingIngredient
from src.llm.scoring import build_match_response, compute_match_score
from src.llm.service import MatchCandidate, MatchOutcome

USAGE = LLMUsage(
    prompt_tokens=395,
    output_tokens=225,
    thought_tokens=0,
    image_tokens=0,
    cost_usd=0.00044,
    model="fake-matcher",
)


def missing(name: str, substitute: str | None = None) -> MissingIngredient:
    return MissingIngredient(name=name, substitute=substitute)


class TestComputeMatchScore:
    def test_필요_5_미해소_1이면_80(self) -> None:
        required = ["김치", "돼지고기", "두부", "대파", "고춧가루"]
        assert compute_match_score(required, [missing("돼지고기")]) == 80

    def test_substitute로_해소된_부족은_감점_없음(self) -> None:
        required = ["두부", "우유", "간장", "설탕"]
        assert compute_match_score(required, [missing("우유", "두유")]) == 100

    def test_부족_없으면_100(self) -> None:
        assert compute_match_score(["계란", "대파"], []) == 100

    def test_floor다_반올림이_아니라(self) -> None:
        # 3/4 = 75, 2/3 = 66.66… → 66. 과대평가하지 않는다.
        assert compute_match_score(["a", "b", "c", "d"], [missing("d")]) == 75
        assert compute_match_score(["a", "b", "c"], [missing("c")]) == 66

    def test_해소와_미해소가_섞이면_미해소만_감점(self) -> None:
        required = ["a", "b", "c", "d"]
        items = [missing("c", "대체"), missing("d")]
        assert compute_match_score(required, items) == 75

    def test_빈_문자열_substitute는_미해소다(self) -> None:
        # .mjs 스키마는 substitute가 선택 필드라 모델이 빈 문자열을 낼 수 있다 — 해소로 치지 않는다.
        assert compute_match_score(["a", "b"], [missing("b", "")]) == 50

    def test_required가_비면_부족_유무로만_판단(self) -> None:
        # LLM이 필요 목록을 안 준 비정상 — 부족이 없으면 공허하게 100, 있으면 보수적으로 0.
        assert compute_match_score([], []) == 100
        assert compute_match_score([], [missing("우유")]) == 0
        assert compute_match_score([], [missing("우유", "두유")]) == 100

    def test_미해소가_필요보다_많으면_0으로_클램프(self) -> None:
        items = [missing("a"), missing("b"), missing("c")]
        assert compute_match_score(["x", "y"], items) == 0


class TestBuildMatchResponse:
    def test_후보마다_점수를_계산하고_순서·usage를_보존한다(self) -> None:
        outcome = MatchOutcome(
            candidates=[
                MatchCandidate(
                    menu="김치찌개",
                    source="saved",
                    missing=[],
                    reason="냉장고에 있는 재료로 다 돼요.",
                    required=["김치", "돼지고기", "두부", "대파", "고춧가루"],
                ),
                MatchCandidate(
                    menu="애호박볶음",
                    source="generated",
                    missing=[missing("식용유")],
                    reason="애호박이 있어서 금방 만들 수 있어요.",
                    required=["애호박", "대파", "소금", "식용유"],
                ),
            ],
            usage=USAGE,
        )
        response = build_match_response(outcome)
        assert [s.menu for s in response.suggestions] == ["김치찌개", "애호박볶음"]
        assert [s.match_score for s in response.suggestions] == [100, 75]
        assert response.usage == USAGE

    def test_required는_wire로_나가지_않는다(self) -> None:
        outcome = MatchOutcome(
            candidates=[
                MatchCandidate(
                    menu="두부조림",
                    source="generated",
                    missing=[missing("우유", "두유")],
                    reason="두부가 있어요.",
                    required=["두부", "우유", "간장", "설탕"],
                )
            ],
            usage=USAGE,
        )
        dumped = build_match_response(outcome).model_dump()
        assert "required" not in dumped["suggestions"][0]

    def test_후보가_없으면_빈_제안(self) -> None:
        outcome = MatchOutcome(candidates=[], usage=USAGE)
        assert build_match_response(outcome).suggestions == []
