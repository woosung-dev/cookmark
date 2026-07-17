// 카톡 인앱 브라우저 상시 경고 — 여기서 쓰면 기록이 날아간다(#21, G1 #8).
//
// 닫을 수 없다. 파일럿 2주치 데이터가 걸린 문제이고, 한 번 유실되면 되돌릴 방법이 없다.
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

class InAppBrowserBanner extends StatelessWidget {
  const InAppBrowserBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('in-app-browser-banner'),
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: AppColors.dangerBg,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.warning_amber,
                size: 18,
                color: AppColors.danger,
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  '여기서는 기록이 사라질 수 있어요',
                  style: AppTypography.headline.copyWith(
                    color: AppColors.danger,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.sm),
          Text(
            '오른쪽 위 ⋯ 를 눌러 "다른 브라우저로 열기"를 선택해 주세요.\n'
            '그다음 홈 화면에 추가해 두면 다음부터 바로 열려요.',
            style: AppTypography.subhead.copyWith(color: AppColors.text),
          ),
        ],
      ),
    );
  }
}

/// 첫 인식 결과 위 1회성 문구 — 인식 오류를 실패로 느끼지 않게 한다(B 이식, G1 #8).
///
/// 이 앱은 인식이 틀리는 걸 전제로 설계됐다(재료 체크리스트 자체가 그 장치다).
/// 사용자가 그걸 모르면 첫 오인식에서 앱을 접는다.
class ExpectationNote extends StatelessWidget {
  const ExpectationNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('expectation-note'),
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(
        color: AppColors.actionTint,
        borderRadius: BorderRadius.circular(Radii.control),
      ),
      child: Text(
        '인식이 틀려도 괜찮아요 — 체크로 다듬는 게 정상이에요.',
        style: AppTypography.subhead.copyWith(color: AppColors.action),
        textAlign: TextAlign.center,
      ),
    );
  }
}
