// 인식 로딩 — 사진 위 스캔 시머 + 체크박스 스켈레톤 + 단계식 문구(G1 #8)
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../screens/loading_stage.dart';
import '../theme/app_colors.dart';

/// 기다림이 불안하지 않게 만드는 섹션. 원형 스피너는 쓰지 않고
/// 레이아웃 모양의 스켈레톤을 쓴다(DESIGN.md §7).
class ScanningSection extends StatelessWidget {
  const ScanningSection({
    required this.photo,
    required this.stage,
    required this.onCancel,
    super.key,
  });

  final Uint8List? photo;
  final LoadingStage stage;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (photo != null) _ScanningPhoto(photo: photo!),
          const SizedBox(height: 20),
          Text(
            stage.message,
            key: const Key('loading-message'),
            style: t.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          const _ChecklistSkeleton(),
          if (stage.showsCancel) ...[
            const SizedBox(height: 20),
            OutlinedButton(
              key: const Key('cancel-button'),
              onPressed: onCancel,
              child: const Text('취소'),
            ),
          ],
        ],
      ),
    );
  }
}

/// 사진 위를 지나가는 스캔 시머. 사진이 표면 위에 놓이므로 유일하게 그림자를 쓴다(DESIGN.md §5).
class _ScanningPhoto extends StatefulWidget {
  const _ScanningPhoto({required this.photo});

  final Uint8List photo;

  @override
  State<_ScanningPhoto> createState() => _ScanningPhotoState();
}

class _ScanningPhotoState extends State<_ScanningPhoto>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Color(0x1A1D1D1F),
              blurRadius: 20,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(widget.photo, fit: BoxFit.cover),
              AnimatedBuilder(
                animation: _shimmer,
                builder: (context, _) => _ShimmerBand(progress: _shimmer.value),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShimmerBand extends StatelessWidget {
  const _ShimmerBand({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment(-1, -1 + progress * 2),
          end: Alignment(1, -0.6 + progress * 2),
          colors: const [
            Color(0x00FFFFFF),
            Color(0x66FFFFFF),
            Color(0x00FFFFFF),
          ],
        ),
      ),
    );
  }
}

/// 곧 나타날 재료 체크리스트의 모양을 미리 보여준다 — 무엇을 기다리는지 알린다.
class _ChecklistSkeleton extends StatelessWidget {
  const _ChecklistSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < 5; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: AppColors.sunken,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 14,
                    // 길이를 조금씩 달리해 목록처럼 보이게 한다.
                    margin: EdgeInsets.only(right: (i % 3) * 40.0),
                    decoration: BoxDecoration(
                      color: AppColors.sunken,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
