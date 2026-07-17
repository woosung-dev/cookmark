# 원가 산식 유닛 — read_usage가 _gemini.mjs readUsage와 동형인지 T1 #6 실측으로 앵커한다
import pytest
from google.genai import types

from src.llm.gemini import read_usage

PRICE_INPUT = 0.25
PRICE_OUTPUT = 1.5


def test_T1_실측_앵커_인식_1157in_295out_이미지_1064() -> None:
    meta = types.GenerateContentResponseUsageMetadata(
        prompt_token_count=1157,
        candidates_token_count=295,
        prompt_tokens_details=[
            types.ModalityTokenCount(modality=types.MediaModality.TEXT, token_count=93),
            types.ModalityTokenCount(
                modality=types.MediaModality.IMAGE, token_count=1064
            ),
        ],
    )
    usage = read_usage(meta, "gemini-3.1-flash-lite", PRICE_INPUT, PRICE_OUTPUT)
    assert usage.prompt_tokens == 1157
    assert usage.output_tokens == 295
    assert usage.thought_tokens == 0
    assert usage.image_tokens == 1064
    assert usage.model == "gemini-3.1-flash-lite"
    # T1 #6이 공식 단가로 검산한 값 ≈ $0.00073.
    assert usage.cost_usd == pytest.approx(0.00073175, rel=1e-9)


def test_thinking은_output_단가로_과금된다() -> None:
    # 빠뜨리면 원가의 대부분이 증발한다 — T1 #6에서 3.5-flash는 78%였다.
    meta = types.GenerateContentResponseUsageMetadata(
        prompt_token_count=100, candidates_token_count=50, thoughts_token_count=200
    )
    usage = read_usage(meta, "m", PRICE_INPUT, PRICE_OUTPUT)
    assert usage.thought_tokens == 200
    assert usage.cost_usd == pytest.approx(
        100 * PRICE_INPUT / 1_000_000 + 250 * PRICE_OUTPUT / 1_000_000
    )


def test_IMAGE_모달리티만_합산한다() -> None:
    meta = types.GenerateContentResponseUsageMetadata(
        prompt_tokens_details=[
            types.ModalityTokenCount(
                modality=types.MediaModality.IMAGE, token_count=500
            ),
            types.ModalityTokenCount(
                modality=types.MediaModality.IMAGE, token_count=564
            ),
            types.ModalityTokenCount(modality=types.MediaModality.TEXT, token_count=93),
        ]
    )
    assert read_usage(meta, "m", PRICE_INPUT, PRICE_OUTPUT).image_tokens == 1064


def test_필드_전부_None이면_0이다() -> None:
    # SDK의 usage 필드는 전부 Optional — 부재를 0으로 정규화한다(.mjs ?? 0 동형).
    usage = read_usage(
        types.GenerateContentResponseUsageMetadata(), "m", PRICE_INPUT, PRICE_OUTPUT
    )
    assert (
        usage.prompt_tokens,
        usage.output_tokens,
        usage.thought_tokens,
        usage.image_tokens,
        usage.cost_usd,
    ) == (0, 0, 0, 0, 0.0)


def test_메타데이터_자체가_없어도_0이다() -> None:
    usage = read_usage(None, "m", PRICE_INPUT, PRICE_OUTPUT)
    assert usage.prompt_tokens == 0
    assert usage.cost_usd == 0.0
