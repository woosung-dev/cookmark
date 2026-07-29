// 레시피 URL + 제목 입력 폼 — 레시피 북과 온보딩 카드가 같이 쓴다(온보딩은 "그 자리에서 완결", G1 #8).
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../recipe_book_controller.dart';
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

  /// 저장 결과를 돌려받아야 거절을 그 자리에서 말할 수 있다(#127). 두 화면이 이 폼을 공유하므로
  /// 배선이 여기 한 곳이면 온보딩 카드와 레시피 북이 함께 고쳐진다.
  final Future<RecipeAddOutcome> Function(String url, String title) onSubmit;

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

  /// 저장 경로에 닿지도 못하고 거절된 이유 — null이면 할 말이 없다.
  RecipeAddOutcome? _rejection;

  /// 손을 대면 걷는다 — 이미 고친 URL 밑에 "이미 있는 링크예요"가 남아 있으면 그 문구가
  /// 거짓말이 된다. 아래 문구가 "고칠 대상이 필드다"라고 말하는 이상 필드가 문구를 지운다.
  void _clearRejection() {
    if (_rejection != null) setState(() => _rejection = null);
  }

  /// 빈 값 판정을 여기서 하지 않는다 — 컨트롤러가 [RecipeAddOutcome.incomplete]로 답한다.
  /// 두 곳에서 자르면 판정이 갈리고, 갈리면 한쪽만 고쳐진다.
  ///
  /// 거절은 첫 await 전에 결정되므로 마이크로태스크 안에서 돌아온다 — 필드가 비었다 돌아오는
  /// 깜빡임이 없다. 거절이면 입력을 남겨 사용자가 그 자리에서 고칠 수 있게 한다.
  ///
  /// **서버 모드의 저장 실패는 여기 오지 않는다** — [RecipeAddOutcome.accepted]로 와서
  /// 필드가 비워지고, 재시도는 실패 카드가 쥔 그 입력으로 간다(#121). 폼이 그 실패까지
  /// 말하면 카드와 두 번 말하게 된다.
  Future<void> _submit() async {
    final url = _urlController.text.trim();
    final title = _titleController.text.trim();
    _clearRejection();

    final outcome = await widget.onSubmit(url, title);
    if (!mounted) return;

    if (outcome == RecipeAddOutcome.accepted) {
      _urlController.clear();
      _titleController.clear();
    } else {
      setState(() => _rejection = outcome);
    }
  }

  /// busy는 문구가 없다 — 버튼의 "재료를 알아보는 중…"이 이미 그 말을 하고 있고,
  /// 거기 문구를 하나 더 얹으면 진짜 거절 둘이 소음에 묻힌다.
  ///
  /// switch가 exhaustive인 것이 트립와이어다 — [RecipeAddOutcome]에 값이 늘면 컴파일이 깨져
  /// "이건 사용자에게 뭐라고 말하나"를 강제로 답하게 한다(위젯 쪽 기본값으로 조용히 흡수되지 않게).
  String? get _rejectionMessage => switch (_rejection) {
    null || RecipeAddOutcome.accepted || RecipeAddOutcome.busy => null,
    RecipeAddOutcome.duplicateUrl => '이미 레시피 북에 있는 링크예요.',
    RecipeAddOutcome.incomplete => '링크와 제목을 모두 채워주세요.',
  };

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
          onChanged: (_) => _clearRejection(),
          decoration: const InputDecoration(hintText: '레시피 링크 붙여넣기'),
        ),
        const SizedBox(height: Space.sm),
        TextField(
          key: const Key('recipe-title-field'),
          controller: _titleController,
          enabled: active,
          textInputAction: TextInputAction.done,
          onChanged: (_) => _clearRejection(),
          onSubmitted: (_) => _submit(),
          decoration: const InputDecoration(hintText: '무슨 요리인가요? (예: 김치찌개)'),
        ),
        // 거절 사유는 버튼이 아니라 **필드 바로 아래**에 붙인다 — 고칠 대상이 필드다.
        if (_rejectionMessage case final message?) ...[
          const SizedBox(height: Space.sm),
          Text(
            key: const Key('recipe-add-rejection'),
            message,
            style: AppTypography.footnote.copyWith(color: AppColors.danger),
          ),
        ],
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
