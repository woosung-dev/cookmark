// 레시피 북 최하단 "백업" 섹션 — 한 동작 내보내기, 미리보기를 거치는 가져오기(#20, G1 #8).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';
import '../backup_controller.dart';

class BackupSection extends StatefulWidget {
  const BackupSection({super.key, required this.controller});

  final BackupController controller;

  @override
  State<BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<BackupSection> {
  final _importController = TextEditingController();

  @override
  void dispose() {
    _importController.dispose();
    super.dispose();
  }

  Future<void> _copyExport() async {
    final json = await widget.controller.exportJson();
    // 클립보드가 막힌 브라우저에서도 기록은 이미 남았다 — 복사만 실패한다.
    var copied = true;
    try {
      await Clipboard.setData(ClipboardData(text: json));
    } on Object {
      copied = false;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          copied ? '복사했어요. 카톡으로 보내주세요.' : '복사가 안 됐어요. 브라우저에서 직접 복사해주세요.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final merge = controller.pendingMerge;

    return Container(
      key: const Key('backup-section'),
      padding: const EdgeInsets.all(Space.xl),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('백업', style: AppTypography.headline),
          const SizedBox(height: Space.sm),
          Text(
            '일요일 저녁에 한 번, 기록을 복사해서 보내주세요.',
            style: AppTypography.subhead.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: Space.lg),
          SizedBox(
            height: Space.touchMin + 4,
            child: FilledButton(
              key: const Key('backup-export'),
              onPressed: _copyExport,
              child: const Text('기록 복사하기'),
            ),
          ),

          const SizedBox(height: Space.xxl),
          const Text('가져오기', style: AppTypography.headline),
          const SizedBox(height: Space.sm),
          TextField(
            key: const Key('backup-import-field'),
            controller: _importController,
            maxLines: 3,
            decoration: const InputDecoration(hintText: '받은 기록을 여기에 붙여넣기'),
          ),
          const SizedBox(height: Space.sm),
          SizedBox(
            height: Space.touchMin,
            child: OutlinedButton(
              key: const Key('backup-preview'),
              onPressed: () =>
                  controller.previewImport(_importController.text.trim()),
              child: const Text('무엇이 들어올지 보기'),
            ),
          ),

          if (controller.importError != null) ...[
            const SizedBox(height: Space.md),
            Text(
              controller.importError!,
              key: const Key('backup-import-error'),
              style: AppTypography.subhead.copyWith(color: AppColors.danger),
            ),
          ],

          // 병합 미리보기 — 확정하기 전에 무엇이 들어오는지 보여준다(C 이식).
          if (merge != null) ...[
            const SizedBox(height: Space.lg),
            Container(
              key: const Key('merge-preview'),
              padding: const EdgeInsets.all(Space.lg),
              decoration: BoxDecoration(
                color: AppColors.sunken,
                borderRadius: BorderRadius.circular(Radii.control),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    merge.changesNothing
                        ? '새로 들어올 레시피가 없어요 — 이미 다 있어요.'
                        : '레시피 ${merge.newRecipes.length}개가 새로 들어와요.',
                    style: AppTypography.subhead,
                  ),
                  if (merge.duplicateRecipeCount > 0) ...[
                    const SizedBox(height: Space.xs),
                    Text(
                      '겹치는 레시피 ${merge.duplicateRecipeCount}개는 건너뜁니다.',
                      style: AppTypography.footnote.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                  const SizedBox(height: Space.xs),
                  Text(
                    '레시피만 가져옵니다. 이 기기의 기록은 그대로예요.',
                    style: AppTypography.footnote.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                  if (merge.newRecipes.isNotEmpty) ...[
                    const SizedBox(height: Space.sm),
                    Text(
                      merge.newRecipes.map((r) => r.title).join(' · '),
                      style: AppTypography.footnote.copyWith(
                        color: AppColors.muted,
                      ),
                    ),
                  ],
                  const SizedBox(height: Space.lg),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: Space.touchMin,
                          child: FilledButton(
                            key: const Key('backup-confirm'),
                            onPressed: merge.changesNothing
                                ? null
                                : () async {
                                    await controller.confirmImport();
                                    _importController.clear();
                                  },
                            child: const Text('가져오기'),
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.md),
                      Expanded(
                        child: SizedBox(
                          height: Space.touchMin,
                          child: OutlinedButton(
                            key: const Key('backup-cancel'),
                            onPressed: controller.cancelImport,
                            child: const Text('취소'),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 7일 경과 리마인더 — 주간 성적표 카피(C 이식, G1 #8).
///
/// 업로드와 이거 했어요 횟수만 보인다. 수동 수정 수는 절대 노출하지 않는다(ADR-0004).
class WeeklyReportBanner extends StatelessWidget {
  const WeeklyReportBanner({
    super.key,
    required this.copy,
    required this.onTap,
  });

  final String copy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const Key('weekly-report-banner'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(Radii.control),
      child: Container(
        constraints: const BoxConstraints(minHeight: Space.touchMin),
        padding: const EdgeInsets.symmetric(
          horizontal: Space.lg,
          vertical: Space.md,
        ),
        decoration: BoxDecoration(
          color: AppColors.actionTint,
          borderRadius: BorderRadius.circular(Radii.control),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                copy,
                style: AppTypography.subhead.copyWith(color: AppColors.action),
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: AppColors.action),
          ],
        ),
      ),
    );
  }
}
