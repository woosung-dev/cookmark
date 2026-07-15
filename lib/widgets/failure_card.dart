// 인식 실패의 인라인 카드 — 막다른 에러 화면 없이 루프를 잇는다(G1 #8)
import 'package:flutter/material.dart';

import '../llm/recognizer.dart';
import '../theme/app_colors.dart';

/// 실패를 해당 섹션 자리에서 처리한다. 별도 에러 화면으로 보내지 않는다 —
/// 냉장고 앞에서 흐름이 끊기면 루프 자체가 죽는다.
///
/// #14는 "다시 시도"까지다. "직접 입력으로 계속"(빈 체크리스트 폴백)은 #21이 붙인다 —
/// 직접 추가 수단이 #15에서 생기기 전에는 빈 체크리스트가 막다른 길이라 폴백이 되지 않는다.
class FailureCard extends StatelessWidget {
  const FailureCard({required this.reason, required this.onRetry, super.key});

  final FailureReason reason;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final (title, detail) = _copy;

    return Container(
      key: const Key('failure-card'),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: t.titleMedium),
          const SizedBox(height: 8),
          Text(detail, style: t.bodyMedium?.copyWith(color: AppColors.muted)),
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('retry-button'),
            onPressed: onRetry,
            child: const Text('다시 시도'),
          ),
        ],
      ),
    );
  }

  (String, String) get _copy => switch (reason) {
    FailureReason.empty => ('재료를 찾지 못했어요', '조금 더 밝은 곳에서 다시 찍어 보시겠어요?'),
    FailureReason.lowQuality => ('사진을 읽지 못했어요', '다른 사진으로 다시 시도해 주세요.'),
    FailureReason.timeout => ('시간이 너무 오래 걸렸어요', '연결이 느린 것 같아요. 다시 시도해 주세요.'),
    FailureReason.server => ('인식에 실패했어요', '잠시 후 다시 시도해 주세요.'),
  };
}
