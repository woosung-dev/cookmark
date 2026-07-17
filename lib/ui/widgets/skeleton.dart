// 스켈레톤 로딩 프리미티브 — 원형 스피너 대신 곧 나타날 레이아웃의 모양을 보여준다(DESIGN.md §7).
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// sunken 색 블록 하나 — 아직 없는 요소의 자리를 미리 잡는다.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    required this.radius,
  });

  /// [double.infinity]이면 부모 너비를 채운다.
  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: AppColors.sunken,
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

/// 자식을 은은하게 맥동시킨다 — [animation]은 1.4s 반복을 가정한다.
class Shimmer extends StatelessWidget {
  const Shimmer({super.key, required this.animation, required this.child});

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Opacity(
        opacity: 0.55 + 0.45 * (1 - (animation.value * 2 - 1).abs()),
        child: child,
      ),
      child: child,
    );
  }
}
