// 실패는 전부 해당 섹션의 인라인 카드로 해소한다 — 막다른 에러 화면을 만들지 않는다(G1 #8).
import 'package:flutter/material.dart';

import '../../llm/llm_gateway.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

class FailureCard extends StatelessWidget {
  const FailureCard({
    super.key,
    required this.kind,
    required this.onRetry,
    required this.onContinueManually,
  });

  final LlmFailureKind kind;
  final VoidCallback onRetry;

  /// "직접 입력으로 계속" — 빈 체크리스트 폴백. 인식이 죽어도 루프는 이어진다.
  final VoidCallback onContinueManually;

  String get _message => switch (kind) {
    LlmFailureKind.empty => '재료를 하나도 찾지 못했어요.',
    LlmFailureKind.lowQuality => '사진이 어두워서 잘 안 보여요.',
    LlmFailureKind.timeout => '시간이 너무 오래 걸렸어요.',
    LlmFailureKind.error => '인식에 실패했어요.',
  };

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
            '다시 시도하거나, 재료를 직접 입력해서 계속할 수 있어요.',
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
                    child: const Text('직접 입력으로 계속'),
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
