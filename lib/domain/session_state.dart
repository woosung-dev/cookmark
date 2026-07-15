// 브라우저를 닫았다 열어도 이어갈 마지막 상태 — 냉장고 앞에서 끊긴 흐름을 잇는다(#15).
import 'package:flutter/foundation.dart';

import 'ingredient.dart';

/// 저장되는 세션. 인식 중이던 호출은 복원하지 않는다 — 그 요청은 이미 사라졌고,
/// 되살리면 사용자가 올린 적 없는 사진의 결과를 보게 된다.
@immutable
class SessionState {
  const SessionState({required this.ingredients});

  final List<Ingredient> ingredients;

  Map<String, Object?> toJson() => {
    'ingredients': [for (final i in ingredients) i.toJson()],
  };

  factory SessionState.fromJson(Map<String, Object?> json) => SessionState(
    ingredients: [
      for (final i in json['ingredients']! as List<Object?>)
        Ingredient.fromJson((i! as Map).cast<String, Object?>()),
    ],
  );
}
