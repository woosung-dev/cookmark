// 빠진 재료를 타이핑 마찰 없이 넣는 자리 — 하단 고정 추가 바 + "자주 쓰는 재료" 칩(G1 #8).
import 'package:flutter/material.dart';

import '../../domain/app_event.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

class AddIngredientBar extends StatefulWidget {
  const AddIngredientBar({
    super.key,
    required this.frequent,
    required this.onAdd,
  });

  /// 빈도 기반 "자주 쓰는 재료" 칩 8개. 이력이 없으면 비어 있다.
  final List<String> frequent;

  /// 경로를 함께 넘긴다 — 타이핑인지 칩인지가 분석에서 갈린다(ADR-0003).
  final void Function(String name, EditPath path) onAdd;

  @override
  State<AddIngredientBar> createState() => _AddIngredientBarState();
}

class _AddIngredientBarState extends State<AddIngredientBar> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    widget.onAdd(name, EditPath.typing);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        Space.screenPad,
        Space.md,
        Space.screenPad,
        Space.md,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.frequent.isNotEmpty) ...[
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: widget.frequent.length,
                  separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
                  itemBuilder: (context, index) {
                    final name = widget.frequent[index];
                    return _Chip(
                      key: Key('frequent-chip-$name'),
                      label: name,
                      onTap: () => widget.onAdd(name, EditPath.frequentChip),
                    );
                  },
                ),
              ),
              const SizedBox(height: Space.md),
            ],
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('add-ingredient-field'),
                    controller: _controller,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(hintText: '빠진 재료 추가'),
                  ),
                ),
                const SizedBox(width: Space.sm),
                SizedBox(
                  height: Space.touchMin,
                  child: FilledButton(
                    key: const Key('add-ingredient-submit'),
                    onPressed: _submit,
                    child: const Text('추가'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.chip),
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: Space.md),
        decoration: BoxDecoration(
          color: AppColors.sunken,
          borderRadius: BorderRadius.circular(Radii.chip),
        ),
        child: Text(label, style: AppTypography.subhead),
      ),
    );
  }
}
