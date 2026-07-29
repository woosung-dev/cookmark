// 실패는 전부 해당 섹션의 인라인 카드로 해소한다 — 막다른 에러 화면을 만들지 않는다(G1 #8).
import 'package:flutter/material.dart';

import '../../llm/llm_gateway.dart';
import '../main_controller.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import 'pressable_scale.dart';
import 'report_hint.dart';

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

  /// 서버 도달 실패는 단계와 무관하게 같은 뜻이라 맨 앞에서 가져간다 — 아래 단계별 아름보다
  /// 먼저 와야 매칭의 캐치올에 삼켜지지 않는다(Dart switch는 순서가 우선한다).
  ///
  /// "연결"이라 쓰는 이유 — 이 실패는 네트워크·서버·파싱을 뭉친 값이라 끊긴 지점이 우리 서버일
  /// 수도, 사용자 회선일 수도 있다. 어느 쪽이든 참이면서 "내 사진이 별로였나"를 끊는 말이다.
  ///
  /// timeout은 [LlmFailureBlame.isServerSide]가 참인데도 여기서 갈리지 않는다 — 의도한 것이다.
  /// "오래 걸렸다"가 "연결이 안 된다"보다 사용자가 겪은 일을 정확히 말하고, 신고가 필요하다는
  /// 사실은 헤드라인이 아니라 아래 신고 유도 줄이 전한다. 문구와 귀책은 같은 축이 아니다.
  String get _message => switch ((stage, kind)) {
    (_, LlmFailureKind.error) => '지금 연결에 문제가 있어요.',
    (FailureStage.matching, LlmFailureKind.empty) => '지금 재료로 만들 만한 걸 찾지 못했어요.',
    (FailureStage.matching, LlmFailureKind.timeout) => '메뉴를 고르는 데 시간이 너무 걸렸어요.',
    (FailureStage.matching, _) => '메뉴를 고르지 못했어요.',
    (_, LlmFailureKind.empty) => '재료를 하나도 찾지 못했어요.',
    (_, LlmFailureKind.lowQuality) => '사진이 어두워서 잘 안 보여요.',
    (_, LlmFailureKind.timeout) => '시간이 너무 오래 걸렸어요.',
  };

  /// 서버 쪽 실패에서는 "네 탓이 아니다"를 먼저 말한다 — 이 한 줄이 없으면 사용자는 사진이나
  /// 재료를 손보러 가고, 정작 파운더가 알아야 할 장애는 아무 데도 남지 않는다.
  String get _help => switch ((kind.isServerSide, stage)) {
    (true, FailureStage.matching) => '재료 문제가 아니에요. 잠시 뒤 다시 시도해 볼 수 있어요.',
    (true, _) => '사진 문제가 아니에요. 잠시 뒤 다시 시도해 볼 수 있어요.',
    (false, FailureStage.matching) => '다시 시도하거나, 재료를 손보고 다시 올 수 있어요.',
    (false, _) => '다시 시도하거나, 재료를 직접 입력해서 계속할 수 있어요.',
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
            key: const Key('failure-headline'),
            _message,
            style: AppTypography.headline.copyWith(color: AppColors.danger),
          ),
          const SizedBox(height: Space.sm),
          Text(
            _help,
            style: AppTypography.subhead.copyWith(color: AppColors.text),
          ),
          // 신고 유도는 서버 쪽 실패에만 붙는다. 파운더는 원격 코호트의 장애를 이 한 줄로만 알고,
          // 알아야 roll-forward가 발동한다 — 없으면 "2주 무사고"가 무사고와 조용한 이탈을
          // 구분하지 못한다(스펙 #161 G절). 사용자 입력 실패까지 붙이면 진짜 신고가 소음에 묻힌다.
          if (kind.isServerSide) ...[
            const SizedBox(height: Space.sm),
            const ReportHint(key: Key('failure-report-hint')),
          ],
          const SizedBox(height: Space.xl),
          // 세로 스택 — 폴백 문구가 길어 반칸에서 두 줄로 접히지 않게(전폭 각각).
          SizedBox(
            height: Space.touchMin,
            child: PressableScale(
              child: FilledButton(
                key: const Key('failure-retry'),
                onPressed: onRetry,
                child: const Text('다시 시도'),
              ),
            ),
          ),
          const SizedBox(height: Space.sm),
          SizedBox(
            height: Space.touchMin,
            child: OutlinedButton(
              key: const Key('failure-manual'),
              onPressed: onContinueManually,
              child: Text(_fallbackLabel),
            ),
          ),
        ],
      ),
    );
  }
}
