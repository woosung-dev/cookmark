// confidence 3단의 초기 상태를 보여주는 체크박스 — DESIGN.md §7 "confidence 체크박스".
import 'package:flutter/material.dart';

import '../../domain/ingredient.dart';
import '../../theme/app_colors.dart';

/// high=채워진 체크 / medium=체크+물음표 점 / low=빈 체크 dim.
///
/// 이 초기 상태는 수동 수정 산식과 한 몸이다(ADR-0003) — 표시를 바꾸기 전에 산식을 먼저 본다.
class ConfidenceCheckbox extends StatelessWidget {
  const ConfidenceCheckbox({
    super.key,
    required this.checked,
    required this.confidence,
  });

  final bool checked;

  /// null = 사용자가 직접 추가한 항목(인식을 거치지 않았다).
  final Confidence? confidence;

  static const _size = 22.0;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: checked ? AppColors.action : Colors.transparent,
        border: Border.all(
          color: checked ? AppColors.action : AppColors.hairline,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: checked
          ? const Icon(Icons.check, size: 16, color: AppColors.onAction)
          : null,
    );

    if (confidence != Confidence.medium) return box;

    // 물음표 점 — "체크는 해뒀지만 확인해 보라"는 신호. 색만으로 말하지 않는다.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        box,
        Positioned(
          right: -3,
          top: -3,
          child: Container(
            width: 12,
            height: 12,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.buyFg,
              shape: BoxShape.circle,
            ),
            child: const Text(
              '?',
              style: TextStyle(
                color: AppColors.onAction,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                height: 1.1,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
