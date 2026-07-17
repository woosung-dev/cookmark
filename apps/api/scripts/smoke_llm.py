# 실 Gemini 스모크 — CI 밖 수동 검증 전용(티켓 #101 AC 7). 이식된 실 코드 경로(설정→팩토리→SDK→파싱)를 그대로 탄다.
#
# 사용법 (apps/api에서, GEMINI_API_KEY는 .env.local 또는 env로 공급).
#   uv run python scripts/smoke_llm.py                # 텍스트 2건(추출·매칭) — 원가 ≈ $0.001 미만
#   uv run python scripts/smoke_llm.py --image 사진.jpg  # + 인식 1건 — 총 ≈ $0.002 미만
import argparse
import asyncio
from pathlib import Path

from src.llm.dependencies import _gemini_service
from src.llm.schemas import LLMUsage, MatchRecipe
from src.llm.scoring import build_match_response

SMOKE_RECIPE = MatchRecipe(
    title="김치찌개", ingredients=["김치", "돼지고기", "두부", "대파", "고춧가루"]
)
SMOKE_INGREDIENTS = ["대파", "계란", "두부", "김치"]


def _print_usage(label: str, usage: LLMUsage) -> None:
    print(
        f"  [{label}] model={usage.model} prompt={usage.prompt_tokens} "
        f"output={usage.output_tokens} thought={usage.thought_tokens} "
        f"image={usage.image_tokens} cost=${usage.cost_usd:.5f}"
    )


async def main(image_path: Path | None) -> None:
    service = _gemini_service()
    total = 0.0

    extraction = await service.extract("김치찌개")
    print(f"추출: {extraction.ingredients}")
    _print_usage("추출", extraction.usage)
    total += extraction.usage.cost_usd

    outcome = await service.match(SMOKE_INGREDIENTS, [SMOKE_RECIPE])
    response = build_match_response(outcome)
    for suggestion in response.suggestions:
        missing = ", ".join(m.name for m in suggestion.missing) or "없음"
        print(
            f"매칭: {suggestion.menu} ({suggestion.source}) "
            f"match_score={suggestion.match_score} 부족={missing}"
        )
    _print_usage("매칭", outcome.usage)
    total += outcome.usage.cost_usd

    if image_path is not None:
        recognition = await service.recognize(image_path.read_bytes())
        listed = [f"{i.name}/{i.confidence}" for i in recognition.ingredients]
        print(f"인식: {listed} low_quality={recognition.low_quality}")
        _print_usage("인식", recognition.usage)
        total += recognition.usage.cost_usd

    print(f"총 원가: ${total:.5f}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="실 Gemini 스모크 — CI 밖 수동 전용.")
    parser.add_argument(
        "--image",
        type=Path,
        default=None,
        help="인식까지 돌릴 로컬 JPEG 경로 (권장 768px)",
    )
    args = parser.parse_args()
    asyncio.run(main(args.image))
