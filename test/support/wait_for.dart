// 상태 변화를 기다리는 헬퍼 — 임의의 sleep으로 타이밍을 찍으면 느린 기계에서 깨진다.
import 'dart:async';

import 'package:flutter/foundation.dart';

/// [predicate]가 참이 될 때까지 [notifier]의 알림을 기다린다.
Future<void> waitFor(ChangeNotifier notifier, bool Function() predicate) {
  if (predicate()) return Future<void>.value();

  final completer = Completer<void>();
  void listener() {
    if (predicate() && !completer.isCompleted) {
      notifier.removeListener(listener);
      completer.complete();
    }
  }

  notifier.addListener(listener);
  return completer.future;
}
