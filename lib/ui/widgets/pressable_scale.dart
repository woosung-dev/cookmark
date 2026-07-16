// 눌림에 살짝 축소되는 래퍼 — DESIGN.md §7 primary "active scale(0.98)". 탭은 자식이 처리한다.
import 'package:flutter/widgets.dart';

/// primary 버튼을 감싸 눌림 피드백만 준다.
///
/// `Listener`는 포인터를 흡수하지 않아(deferToChild) 아래 버튼의 `onPressed`가 그대로 뜬다 —
/// 시각 피드백만 얹고 히트테스트는 자식에게 넘긴다(E2E `tester.tap` 정상 동작).
class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.child, this.scale = 0.98});

  final Widget child;
  final double scale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(true),
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
