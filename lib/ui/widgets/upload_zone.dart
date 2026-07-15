// 외길의 출발점 — 냉장고 사진 1장을 받는다. 타이핑 없이 재고 파악을 시작하는 자리다.
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

class UploadZone extends StatelessWidget {
  const UploadZone({super.key, required this.onPick});

  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: Space.xxxl,
        horizontal: Space.xl,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.photo_camera_outlined,
            size: 40,
            color: AppColors.brand,
          ),
          const SizedBox(height: Space.lg),
          Text('냉장고 사진 한 장이면 돼요', style: AppTypography.headline),
          const SizedBox(height: Space.sm),
          Text(
            '안에 뭐가 있는지 찍어서 올려주세요.',
            style: AppTypography.subhead.copyWith(color: AppColors.muted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: Space.xl),
          SizedBox(
            width: double.infinity,
            height: Space.touchMin + 4,
            child: FilledButton(
              key: const Key('upload-photo'),
              onPressed: onPick,
              child: const Text('사진 올리기'),
            ),
          ),
        ],
      ),
    );
  }
}
