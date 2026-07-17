// 온보딩 상단 브랜드 히어로 — 홍시→차콜 그라디언트 위 흰 워드마크(사진 백엔드 오면 교체, ADR-0007).
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

/// 업로드 진입 상단의 브랜드 순간. 목업 화면 1의 따뜻한 히어로를 사진 없이 재현한다.
///
/// 흰 텍스트는 브랜드 필(#E8552D, 대비 3.6)이 아니라 그라디언트 하단의 차콜 위에 놓여 AA를 만족한다.
class BrandHero extends StatelessWidget {
  const BrandHero({super.key});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.card),
      child: Container(
        height: 200,
        alignment: Alignment.bottomLeft,
        padding: const EdgeInsets.all(Space.xl),
        decoration: const BoxDecoration(
          // 홍시(위) → 곶감 딥레드 → 차콜(아래). 워드마크가 놓이는 하단은 흰 텍스트 대비를 확보.
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.brand, Color(0xFFB23A25), Color(0xFF241511)],
            stops: [0.0, 0.4, 0.82],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '냉파',
              style: AppTypography.largeTitle.copyWith(
                fontSize: 32,
                color: AppColors.onAction,
              ),
            ),
            const SizedBox(height: Space.xs),
            Text(
              '냉장고 사진 한 장으로,\n오늘 뭐 해먹을지 끝내요.',
              style: AppTypography.subhead.copyWith(
                color: AppColors.onAction,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
