// 인식 대기 중 문구가 바뀌는 단계 — 기다림이 불안하지 않게 하는 장치(G1 #8).
import 'package:flutter/foundation.dart';

/// 인식 로딩의 단계식 문구. 경계는 G1 #8 확정값이다 — 0~3초 / 3~10초 / 10초(취소 등장) / 30초(타임아웃).
enum LoadingStage {
  /// 0~3초
  early('재료를 찾는 중이에요'),

  /// 3~10초
  mid('거의 다 됐어요'),

  /// 10초~ — 여기서부터 취소 버튼이 등장한다
  slow('조금만 더 기다려 주세요');

  const LoadingStage(this.message);

  final String message;

  /// 취소 버튼은 10초부터 보인다.
  bool get showsCancel => this == LoadingStage.slow;
}

/// 경계값은 "이상"이 아니라 "초과" 기준이다 — 3초 정각은 아직 early다.
@visibleForTesting
const stageBoundaries = (
  mid: Duration(seconds: 3),
  slow: Duration(seconds: 10),
);

LoadingStage stageFor(Duration elapsed) {
  if (elapsed > stageBoundaries.slow) return LoadingStage.slow;
  if (elapsed > stageBoundaries.mid) return LoadingStage.mid;
  return LoadingStage.early;
}
