// 뭉뚱그림 항목의 점선 칩 — 구체 재료로 치환하기 전에는 매칭에 가지 않는다(ADR-0002).
import 'package:flutter/material.dart';

import '../../domain/ingredient.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

/// "반찬통" 같은 항목을 체크리스트 본문과 분리해 보여준다.
///
/// 치환은 보너스다 — 사용자의 실제 재고 지식을 매칭 데이터로 바꾼다. 안 해도 루프는 굴러간다.
class VagueChips extends StatelessWidget {
  const VagueChips({
    super.key,
    required this.items,
    required this.onSubstitute,
    required this.onDismiss,
  });

  final List<Ingredient> items;

  /// 인라인 치환 — "멸치볶음, 김".
  final void Function(String name, String replacements) onSubstitute;

  /// 오탐 복귀 — 탭 1회로 일반 항목이 된다.
  final void Function(String name) onDismiss;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: Space.xs, bottom: Space.sm),
          child: Text(
            '이건 뭐였나요?',
            style: AppTypography.footnote.copyWith(color: AppColors.muted),
          ),
        ),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: Space.sm),
            child: _VagueChip(
              item: item,
              onSubstitute: onSubstitute,
              onDismiss: onDismiss,
            ),
          ),
      ],
    );
  }
}

class _VagueChip extends StatefulWidget {
  const _VagueChip({
    required this.item,
    required this.onSubstitute,
    required this.onDismiss,
  });

  final Ingredient item;
  final void Function(String name, String replacements) onSubstitute;
  final void Function(String name) onDismiss;

  @override
  State<_VagueChip> createState() => _VagueChipState();
}

class _VagueChipState extends State<_VagueChip> {
  final _controller = TextEditingController();
  bool _editing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _controller.text.trim();
    if (raw.isEmpty) return;
    widget.onSubstitute(widget.item.name, raw);
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.item.name;

    return CustomPaint(
      // 점선 — 확정된 재료가 아니라는 시각 신호.
      painter: const _DashedBorderPainter(color: AppColors.hairline),
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: _editing
            ? Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: Key('vague-input-$name'),
                      controller: _controller,
                      autofocus: true,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        hintText: '$name 안에 뭐가 있었나요? (쉼표로 구분)',
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  SizedBox(
                    height: Space.touchMin,
                    child: FilledButton(
                      key: Key('vague-submit-$name'),
                      onPressed: _submit,
                      child: const Text('바꾸기'),
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    child: InkWell(
                      key: Key('vague-chip-$name'),
                      onTap: () => setState(() => _editing = true),
                      child: Container(
                        constraints: const BoxConstraints(
                          minHeight: Space.touchMin,
                        ),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          name,
                          style: AppTypography.body.copyWith(
                            color: AppColors.muted,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 오탐이면 이 탭 1회로 일반 항목이 된다.
                  TextButton(
                    key: Key('vague-dismiss-$name'),
                    onPressed: () => widget.onDismiss(name),
                    child: const Text('맞아요'),
                  ),
                ],
              ),
      ),
    );
  }
}

/// 점선 테두리. Flutter 기본 Border에는 점선이 없어 직접 그린다.
class _DashedBorderPainter extends CustomPainter {
  const _DashedBorderPainter({required this.color});

  final Color color;

  static const _dash = 4.0;
  static const _gap = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          const Radius.circular(Radii.chip),
        ),
      );

    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(metric.extractPath(distance, distance + _dash), paint);
        distance += _dash + _gap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}
