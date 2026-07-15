// 레시피 북 — 사용자가 신뢰하는 저장 레시피의 화면. 앱의 두 번째이자 마지막 화면(ADR-0001).
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// URL 저장·온보딩 카드는 #17, 백업 섹션은 #20에서 붙는다.
class RecipeBookPage extends StatelessWidget {
  const RecipeBookPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('레시피 북')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(Space.screenPad),
            child: Text(
              '믿고 보는 레시피를 여기에 모읍니다.',
              style: AppTypography.body.copyWith(color: AppColors.muted),
            ),
          ),
        ),
      ),
    );
  }
}
