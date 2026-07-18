// 음식 사진 자리 — 실제 이미지는 백엔드(URL og:image) 이월. 지금은 홍시-틴트 플레이스홀더.
//
// 제안 카드·상세·레시피 북 썸네일이 공유한다. 자산이 붙기 전까지 "사진이 올 자리"를 온기 있게 채운다.
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

class PhotoPlaceholder extends StatelessWidget {
  const PhotoPlaceholder({
    super.key,
    this.aspectRatio,
    this.width,
    this.height,
    this.borderRadius = 0,
    this.icon = Icons.restaurant_menu,
    this.iconSize = 40,
    this.overlay,
  });

  /// [aspectRatio]가 있으면 그 비율로, 없으면 [width]/[height]로 채운다.
  final double? aspectRatio;
  final double? width;
  final double? height;
  final double borderRadius;
  final IconData icon;
  final double iconSize;

  /// 사진 위에 얹는 것 — 순위·매칭 배지 등(Stack으로 올린다).
  final Widget? overlay;

  @override
  Widget build(BuildContext context) {
    Widget box = DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.actionTint,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Center(
        child: Icon(icon, size: iconSize, color: AppColors.brand),
      ),
    );

    if (overlay != null) {
      box = Stack(
        fit: StackFit.expand,
        children: [
          if (borderRadius > 0)
            ClipRRect(
              borderRadius: BorderRadius.circular(borderRadius),
              child: box,
            )
          else
            box,
          overlay!,
        ],
      );
    }

    if (aspectRatio != null) {
      return AspectRatio(aspectRatio: aspectRatio!, child: box);
    }
    return SizedBox(width: width, height: height, child: box);
  }
}

/// 사진 위 좌상단 배지 — "1위 · 96% 일치"(순위는 실값, 매칭%는 백엔드 이월 placeholder).
class MatchBadge extends StatelessWidget {
  const MatchBadge({super.key, required this.rank, required this.percent});

  final int rank;
  final int percent;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: Space.md,
      left: Space.md,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.sm,
          vertical: Space.xs,
        ),
        decoration: BoxDecoration(
          color: const Color(0xCC1D1D1F), // 반투명 먹빛 — 사진 위 가독성.
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Text(
          '$rank위 · $percent% 일치',
          style: AppTypography.caption.copyWith(color: AppColors.onAction),
        ),
      ),
    );
  }
}
