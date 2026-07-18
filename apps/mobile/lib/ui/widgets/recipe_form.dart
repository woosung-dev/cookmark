// 레시피 URL + 제목 입력 폼 — 레시피 북과 온보딩 카드가 같이 쓴다(온보딩은 "그 자리에서 완결", G1 #8).
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import 'pressable_scale.dart';

class RecipeForm extends StatefulWidget {
  const RecipeForm({
    super.key,
    required this.saving,
    this.enabled = true,
    required this.onSubmit,
  });

  /// 추출 호출이 도는 동안 참.
  final bool saving;

  /// 폼 전체 비활성 — 서버 하이드레이트가 실패한 동안 저장 입력을 막는다(#121).
  final bool enabled;

  final void Function(String url, String title) onSubmit;

  @override
  State<RecipeForm> createState() => _RecipeFormState();
}

class _RecipeFormState extends State<RecipeForm> {
  final _urlController = TextEditingController();
  final _titleController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  void _submit() {
    final url = _urlController.text.trim();
    final title = _titleController.text.trim();
    if (url.isEmpty || title.isEmpty) return;
    widget.onSubmit(url, title);
    _urlController.clear();
    _titleController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && !widget.saving;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('recipe-url-field'),
          controller: _urlController,
          enabled: active,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: '레시피 링크 붙여넣기'),
        ),
        const SizedBox(height: Space.sm),
        TextField(
          key: const Key('recipe-title-field'),
          controller: _titleController,
          enabled: active,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(hintText: '무슨 요리인가요? (예: 김치찌개)'),
        ),
        const SizedBox(height: Space.md),
        SizedBox(
          height: Space.touchMin + 4,
          child: PressableScale(
            enabled: active,
            child: FilledButton(
              key: const Key('recipe-submit'),
              onPressed: active ? _submit : null,
              child: Text(widget.saving ? '재료를 알아보는 중…' : '레시피 북에 담기'),
            ),
          ),
        ),
        const SizedBox(height: Space.sm),
        Text(
          '제목으로 재료를 짐작해 둡니다. 영상 내용은 가져오지 않아요.',
          style: AppTypography.caption.copyWith(color: AppColors.muted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
