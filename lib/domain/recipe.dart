// 레시피 북의 항목 — 사용자가 직접 저장한, 출처 있는 레시피(CONTEXT.md 글로서리). 냉파 차별화의 근거다.
import 'package:freezed_annotation/freezed_annotation.dart';

part 'recipe.freezed.dart';
part 'recipe.g.dart';

/// URL이 곧 식별자다 — 백업 병합의 중복 제거도 URL 기준이다(#20).
///
/// 본문·자막은 다루지 않는다(스펙 Out of scope). [ingredients]는 제목만 보고 LLM이 추론한 것이다.
@freezed
abstract class Recipe with _$Recipe {
  const factory Recipe({
    required String url,
    required String title,
    required List<String> ingredients,
  }) = _Recipe;

  factory Recipe.fromJson(Map<String, dynamic> json) => _$RecipeFromJson(json);
}
