// 재료와 confidence 3단 — 인식 결과를 확정 목록으로 다듬는 재료 체크리스트의 도메인 모델
import 'package:flutter/foundation.dart';

/// 재료 인식의 확신도 3단. 초기 체크 상태를 정하며, 이 산식은 ADR-0003의 수동 수정
/// 계측과 한 몸이다 — 파일럿 종료까지 변경 금지.
enum Confidence {
  high,
  medium,
  low;

  /// 프록시 JSON의 문자열을 파싱한다. 계약을 벗어난 값은 `low`로 떨어뜨린다 —
  /// 모르는 값을 체크된 채로 들이면 환각이 매칭을 오염시킨다.
  static Confidence parse(String? raw) => switch (raw) {
    'high' => Confidence.high,
    'medium' => Confidence.medium,
    _ => Confidence.low,
  };
}

/// 재료 체크리스트의 한 행. 해제는 매칭 제외를 뜻하며 삭제 개념은 없다(G1 #8).
@immutable
class Ingredient {
  const Ingredient({
    required this.name,
    required this.confidence,
    required this.checked,
  });

  /// 인식 결과에서 만든다 — high·medium은 체크, low는 해제(ADR-0003).
  factory Ingredient.fromRecognition({
    required String name,
    required Confidence confidence,
  }) => Ingredient(
    name: name,
    confidence: confidence,
    checked: confidence != Confidence.low,
  );

  /// 사용자가 직접 추가한 재료 — 사용자가 봤으므로 high·체크다.
  factory Ingredient.userAdded(String name) =>
      Ingredient(name: name, confidence: Confidence.high, checked: true);

  final String name;
  final Confidence confidence;
  final bool checked;

  Ingredient toggled() =>
      Ingredient(name: name, confidence: confidence, checked: !checked);

  @override
  bool operator ==(Object other) =>
      other is Ingredient &&
      other.name == name &&
      other.confidence == confidence &&
      other.checked == checked;

  @override
  int get hashCode => Object.hash(name, confidence, checked);
}
