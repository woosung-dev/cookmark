// 인식 로딩의 단계식 문구 — 경과 시간을 G1 #8이 정한 단계로 나눈다
/// 인식을 기다리는 동안 보여줄 단계. 경계(3s/10s)는 G1 #8 확정값이다 —
/// 부엌에서 기다리는 사람이 "멈춘 건가?"라고 느끼기 전에 말이 바뀌게 한다.
///
/// 30초 타임아웃은 여기 없다 — 그건 문구가 아니라 인식 자체의 제한 시간이고,
/// [kRecognitionTimeout]으로 호출 경계에서 건다.
enum LoadingStage {
  justStarted('사진에서 재료를 찾고 있어요'),
  stillWorking('재료를 하나씩 확인하는 중이에요'),
  cancellable('조금만 더 기다려 주세요');

  const LoadingStage(this.message);

  /// 사진 위 스캔 시머와 함께 보여줄 문구.
  final String message;

  /// 10초를 넘기면 취소를 내보인다 — 그 전에는 취소가 오히려 불안을 만든다.
  bool get showsCancel => this == LoadingStage.cancellable;

  static LoadingStage forElapsed(Duration elapsed) {
    final s = elapsed.inSeconds;
    if (s >= 10) return LoadingStage.cancellable;
    if (s >= 3) return LoadingStage.stillWorking;
    return LoadingStage.justStarted;
  }
}
