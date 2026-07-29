// 서버 모드에서 레시피 저장(add)이 실패했을 때 폼 아래에 뜨는 인라인 카드 — 502=미저장이 서버 정책(#121).
//
// FailureCard를 확장하지 않는다 — 그쪽은 FailureStage(인식·매칭)에 결합돼 있고
// 'failure-card' key를 쓰므로, 저장 실패는 자기 key를 가진 소형 위젯으로 분리한다.
import 'package:flutter/material.dart';

import '../../data/server_recipe_repository.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import 'pressable_scale.dart';
import 'report_hint.dart';

class RecipeAddFailureCard extends StatelessWidget {
  const RecipeAddFailureCard({
    super.key,
    required this.kind,
    required this.onRetry,
    required this.onDismiss,
  });

  final RecipeApiFailureKind kind;

  /// 실패한 입력(controller.failedAdd)으로 add를 재전송한다 — 폼의 입력과 무관하게 성립한다
  /// (폼이 그 사이 지워졌든 다른 값으로 바뀌었든 실패한 그 입력을 다시 보낸다).
  final VoidCallback onRetry;

  /// 재시도를 포기하고 카드를 접는다(clearAddFailure).
  final VoidCallback onDismiss;

  String get _message => kind == RecipeApiFailureKind.extractionFailed
      ? '재료를 알아내지 못해 저장하지 못했어요'
      : '지금은 저장할 수 없어요';

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('recipe-add-failure-card'),
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
          // 신고 유도는 kind로 가르지 않는다(#127) — [RecipeApiFailureKind]에는 LlmFailureKind의
          // empty·lowQuality 같은 "사용자 입력이 원인인" 값이 하나도 없다. 502조차 서버 LLM 자체
          // 다운일 때만 나고(추출 사다리가 그 앞을 전부 제목 추론으로 강등한다), 나머지 셋은
          // 정의상 서버 도달 실패다. 그래서 LlmFailureBlame 같은 분류 축을 새로 만들지 않는다 —
          // 없는 갈림을 위해 축을 세우면 다음 사람이 그 축을 진짜라고 믿는다.
          const SizedBox(height: Space.sm),
          const ReportHint(key: Key('recipe-add-report-hint')),
          const SizedBox(height: Space.xl),
          SizedBox(
            height: Space.touchMin,
            child: PressableScale(
              child: FilledButton(
                key: const Key('recipe-add-retry'),
                onPressed: onRetry,
                child: const Text('다시 시도'),
              ),
            ),
          ),
          const SizedBox(height: Space.sm),
          SizedBox(
            height: Space.touchMin,
            child: OutlinedButton(
              key: const Key('recipe-add-dismiss'),
              onPressed: onDismiss,
              child: const Text('닫기'),
            ),
          ),
        ],
      ),
    );
  }
}
