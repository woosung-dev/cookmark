// 레시피 북의 항목 — 사용자가 직접 저장한, 출처 있는 레시피(CONTEXT.md 글로서리). 냉파 차별화의 근거다.
import 'package:flutter/foundation.dart';

/// URL이 곧 식별자다 — 백업 병합의 중복 제거도 URL 기준이다(#20).
///
/// 본문·자막은 다루지 않는다(스펙 Out of scope). [ingredients]는 제목만 보고 LLM이 추론한 것이다.
@immutable
class Recipe {
  const Recipe({
    this.id,
    required this.url,
    required this.title,
    required this.ingredients,
  });

  /// 서버 레시피 북의 UUID. 로컬 모드·서버 미반영 상태에선 null.
  /// ==·dedup에 넣지 않는다 — 정체성은 url이고, id는 수송 메타데이터다.
  final String? id;

  final String url;

  /// 사용자가 직접 적은 요리명. 긁어오지 않는다.
  final String title;

  /// 제목에서 추론된 재료. 추출이 실패하면 비어 있을 수 있다 — 그래도 레시피는 저장된다.
  final List<String> ingredients;

  Recipe copyWith({List<String>? ingredients}) => Recipe(
    id: id,
    url: url,
    title: title,
    ingredients: ingredients ?? this.ingredients,
  );

  Map<String, Object?> toJson() => {
    if (id != null) 'id': id,
    'url': url,
    'title': title,
    'ingredients': ingredients,
  };

  factory Recipe.fromJson(Map<String, Object?> json) => Recipe(
    id: json['id'] as String?,
    url: json['url']! as String,
    title: json['title']! as String,
    ingredients: [
      for (final i in json['ingredients'] as List<Object?>? ?? const [])
        i! as String,
    ],
  );

  @override
  bool operator ==(Object other) =>
      other is Recipe &&
      other.url == url &&
      other.title == title &&
      listEquals(other.ingredients, ingredients);

  @override
  int get hashCode => Object.hash(url, title, Object.hashAll(ingredients));

  @override
  String toString() => 'Recipe($title, $url, ${ingredients.length}개 재료)';
}
