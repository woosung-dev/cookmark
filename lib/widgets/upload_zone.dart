// 업로드 존 — 코어 루프의 입구. 첫 방문 상태이자 온보딩 자리(ADR-0001)
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// "냉장고 사진 올리기" 하나로 루프를 연다. 화면당 primary 버튼은 1개(DESIGN.md §7).
class UploadZone extends StatelessWidget {
  const UploadZone({required this.onPick, super.key});

  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.hairline),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.photo_camera_outlined,
                  size: 40,
                  color: AppColors.brand,
                ),
                const SizedBox(height: 16),
                Text(
                  '냉장고 사진 한 장이면 돼요',
                  style: t.titleLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '있는 재료로 오늘 뭘 해먹을지 골라 드릴게요.',
                  style: t.bodyMedium?.copyWith(color: AppColors.muted),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('upload-button'),
            onPressed: onPick,
            child: const Text('냉장고 사진 올리기'),
          ),
        ],
      ),
    );
  }
}
