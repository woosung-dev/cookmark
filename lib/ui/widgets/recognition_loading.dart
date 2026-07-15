// 인식 대기 — 사진 위 스캔 시머 + 체크박스 스켈레톤 + 단계식 문구(G1 #8). 기다림이 불안하지 않게.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../domain/loading_stage.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_theme.dart';

class RecognitionLoading extends StatefulWidget {
  const RecognitionLoading({
    super.key,
    required this.photo,
    required this.startedAt,
    required this.onCancel,
    this.now = DateTime.now,
  });

  final Uint8List? photo;
  final DateTime startedAt;
  final VoidCallback onCancel;

  /// 테스트가 시간을 고정할 수 있게.
  final DateTime Function() now;

  @override
  State<RecognitionLoading> createState() => _RecognitionLoadingState();
}

// 티커가 둘이다 — 시머 애니메이션과 경과 시간 감시. SingleTickerProviderStateMixin은 하나만 허용한다.
class _RecognitionLoadingState extends State<RecognitionLoading>
    with TickerProviderStateMixin {
  late final AnimationController _shimmer;
  late final Ticker _elapsedTicker;
  LoadingStage _stage = LoadingStage.early;

  @override
  void initState() {
    super.initState();
    // late final의 지연 생성에 맡기면, 화면에 뜨기 전에 dispose될 때 dispose가 티커를 새로 만든다.
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _elapsedTicker = createTicker((_) {
      final stage = stageFor(widget.now().difference(widget.startedAt));
      if (stage != _stage) setState(() => _stage = stage);
    })..start();
  }

  @override
  void dispose() {
    _elapsedTicker.dispose();
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.photo != null)
          _ScanningPhoto(photo: widget.photo!, shimmer: _shimmer),
        const SizedBox(height: Space.xl),
        Text(
          _stage.message,
          key: const Key('loading-message'),
          style: AppTypography.body.copyWith(color: AppColors.muted),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: Space.lg),
        _ChecklistSkeleton(shimmer: _shimmer),
        if (_stage.showsCancel) ...[
          const SizedBox(height: Space.lg),
          Center(
            child: TextButton(
              key: const Key('loading-cancel'),
              onPressed: widget.onCancel,
              child: const Text('취소'),
            ),
          ),
        ],
      ],
    );
  }
}

/// 업로드한 냉장고 사진 위를 훑는 스캔 시머. 그림자를 다는 유일한 자리다(DESIGN.md §5).
class _ScanningPhoto extends StatelessWidget {
  const _ScanningPhoto({required this.photo, required this.shimmer});

  final Uint8List photo;
  final Animation<double> shimmer;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        borderRadius: BorderRadius.all(Radius.circular(Radii.photo)),
        boxShadow: Elevations.photo,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.photo),
        child: AspectRatio(
          aspectRatio: 4 / 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.memory(photo, fit: BoxFit.cover),
              AnimatedBuilder(
                animation: shimmer,
                builder: (context, _) => Align(
                  alignment: Alignment(0, shimmer.value * 2 - 1),
                  child: Container(
                    height: 64,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.brand.withValues(alpha: 0),
                          AppColors.brand.withValues(alpha: 0.35),
                          AppColors.brand.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 곧 나타날 재료 체크리스트의 모양을 미리 보여준다 — 원형 스피너 대신(DESIGN.md §7).
class _ChecklistSkeleton extends StatelessWidget {
  const _ChecklistSkeleton({required this.shimmer});

  final Animation<double> shimmer;

  static const _rows = 5;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(Radii.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < _rows; i++) ...[
            if (i > 0) const Divider(indent: Space.lg),
            SizedBox(
              height: Space.rowMin,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                child: Row(
                  children: [
                    _Shimmer(
                      shimmer: shimmer,
                      child: const _Block(width: 22, height: 22, radius: 6),
                    ),
                    const SizedBox(width: Space.md),
                    _Shimmer(
                      shimmer: shimmer,
                      child: _Block(
                        width: 96.0 + (i.isEven ? 40 : 0),
                        height: 14,
                        radius: 7,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({
    required this.width,
    required this.height,
    required this.radius,
  });

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

class _Shimmer extends StatelessWidget {
  const _Shimmer({required this.shimmer, required this.child});

  final Animation<double> shimmer;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shimmer,
      builder: (context, child) => Opacity(
        opacity: 0.55 + 0.45 * (1 - (shimmer.value * 2 - 1).abs()),
        child: child,
      ),
      child: child,
    );
  }
}
