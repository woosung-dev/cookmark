// 실패는 전부 해당 섹션의 인라인 카드로 해소한다 — 막다른 에러 화면을 만들지 않는다(G1 #8).
import 'package:flutter/material.dart';

import '../../llm/llm_gateway.dart';
import '../main_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

class FailureCard extends StatelessWidget {
  const FailureCard({
    super.key,
    required this.kind,
    required this.stage,
    required this.onRetry,
    required this.onContinueManually,
  });

  final LlmFailureKind kind;

  /// 인식 실패와 매칭 실패는 다른 자리에서 나고, 빠져나가는 길도 다르다.
  final FailureStage stage;

  final VoidCallback onRetry;

  /// 인식 실패면 "직접 입력으로 계속"(빈 체크리스트 폴백), 매칭 실패면 재료로 돌아간다.
  /// 어느 쪽이든 루프는 이어진다 — 막다른 화면이 없다(G1 #8).
  final VoidCallback onContinueManually;

  String get _message => switch ((stage, kind)) {
    (FailureStage.matching, LlmFailureKind.empty) => '지금 재료로 만들 만한 걸 찾지 못했어요.',
    (FailureStage.matching, LlmFailureKind.timeout) => '메뉴를 고르는 데 시간이 너무 걸렸어요.',
    (FailureStage.matching, _) => '메뉴를 고르지 못했어요.',
    (_, LlmFailureKind.empty) => '재료를 하나도 찾지 못했어요.',
    (_, LlmFailureKind.lowQuality) => '사진이 어두워서 잘 안 보여요.',
    (_, LlmFailureKind.timeout) => '시간이 너무 오래 걸렸어요.',
    (_, LlmFailureKind.error) => '인식에 실패했어요.',
  };

  String get _fallbackLabel =>
      stage == FailureStage.matching ? '재료 다시 보기' : '직접 입력으로 계속';

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('failure-card'),
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(
        color: AppColors.dangerBg,
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _message,
            style: AppTypography.headline.copyWith(color: AppColors.danger),
          ),
          const SizedBox(height: Space.sm),
          Text(
            stage == FailureStage.matching
                ? '다시 시도하거나, 재료를 손보고 다시 올 수 있어요.'
                : '다시 시도하거나, 재료를 직접 입력해서 계속할 수 있어요.',
            style: AppTypography.subhead.copyWith(color: AppColors.text),
          ),
          const SizedBox(height: Space.xl),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: Space.touchMin,
                  child: FilledButton(
                    key: const Key('failure-retry'),
                    onPressed: onRetry,
                    child: const Text('다시 시도'),
                  ),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: SizedBox(
                  height: Space.touchMin,
                  child: OutlinedButton(
                    key: const Key('failure-manual'),
                    onPressed: onContinueManually,
                    child: Text(_fallbackLabel),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
