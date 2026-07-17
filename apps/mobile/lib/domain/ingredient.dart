// 재료 체크리스트의 항목 — 재료 인식 결과이자 사용자가 체크로 다듬는 대상(CONTEXT.md 글로서리).
import 'package:flutter/foundation.dart';

import 'vague_heuristic.dart';

/// 재료 인식이 항목마다 붙이는 확신도 3단.
enum Confidence {
  high,
  medium,
  low;

  /// 재료 체크리스트의 초기 체크 상태 — high·medium은 체크, low는 해제.
  ///
  /// 이 초기 상태는 수동 수정 산식과 한 몸이다(ADR-0003). 파일럿 종료까지 바꾸지 않는다 —
  /// 바꾸면 킬 기준의 2주 데이터가 비교 불가가 된다.
  bool get initiallyChecked => this != Confidence.low;

  static Confidence? parse(String? raw) => switch (raw) {
    'high' => Confidence.high,
    'medium' => Confidence.medium,
    'low' => Confidence.low,
    _ => null,
  };
}

/// 재료 하나. 이름이 곧 식별자다 — 추가 시 같은 이름은 병합한다.
@immutable
class Ingredient {
  const Ingredient({
    required this.name,
    required this.confidence,
    required this.checked,
    this.isVague = false,
  });

  /// 재료 인식이 내놓은 항목 — 초기 체크 상태는 confidence가 정하고,
  /// 뭉뚱그림 여부는 클라이언트 휴리스틱이 태어날 때 붙인다(ADR-0002).
  Ingredient.recognized({
    required this.name,
    required Confidence this.confidence,
  }) : checked = confidence.initiallyChecked,
       isVague = isVagueItem(name: name, confidence: confidence);

  /// 사용자가 직접 추가한 항목 — 인식을 거치지 않았으므로 confidence가 없고 항상 체크다.
  const Ingredient.added(this.name)
    : confidence = null,
      checked = true,
      isVague = false;

  final String name;

  /// null = 사용자가 직접 추가한 항목.
  final Confidence? confidence;

  /// 해제 = 매칭 제외. 삭제 개념은 없다(G1 #8).
  final bool checked;

  /// 뭉뚱그림 항목 — 점선 칩으로 분리되고, 치환 전에는 매칭에 전송되지 않는다(ADR-0002).
  ///
  /// 사용자가 오탐이라고 하면 false가 된다.
  final bool isVague;

  /// 매칭에 보낼 재료인가. 해제된 것과 미치환 뭉뚱그림은 조용히 빠진다(ADR-0002).
  bool get goesToMatching => checked && !isVague;

  Ingredient copyWith({bool? checked, bool? isVague}) => Ingredient(
    name: name,
    confidence: confidence,
    checked: checked ?? this.checked,
    isVague: isVague ?? this.isVague,
  );

  Map<String, Object?> toJson() => {
    'name': name,
    if (confidence != null) 'confidence': confidence!.name,
    'checked': checked,
    if (isVague) 'isVague': true,
  };

  factory Ingredient.fromJson(Map<String, Object?> json) => Ingredient(
    name: json['name']! as String,
    confidence: Confidence.parse(json['confidence'] as String?),
    checked: json['checked']! as bool,
    isVague: json['isVague'] as bool? ?? false,
  );

  @override
  bool operator ==(Object other) =>
      other is Ingredient &&
      other.name == name &&
      other.confidence == confidence &&
      other.checked == checked &&
      other.isVague == isVague;

  @override
  int get hashCode => Object.hash(name, confidence, checked, isVague);

  @override
  String toString() =>
      'Ingredient($name, $confidence, checked: $checked, vague: $isVague)';
}
