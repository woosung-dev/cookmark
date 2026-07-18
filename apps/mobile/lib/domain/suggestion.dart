// 제안 — 인식된 재료와 레시피 북을 매칭해 내놓는 메뉴(CONTEXT.md 글로서리).
// 한 번에 최대 3개("오늘 할 3개") — 20개의 새로운 결정이 아니라 신뢰된 소수의 답이다.
import 'package:flutter/foundation.dart';

/// 제안이 어디서 왔는지. 출처 라벨은 필수다 — 사용자가 신뢰하는 소스를 우선 고를 수 있어야 한다.
enum SuggestionSource {
  /// 북마크 — "내 레시피 북"
  saved,

  /// 반짝 — "AI 제안"
  generated;

  static SuggestionSource? parse(String? raw) => switch (raw) {
    'saved' => SuggestionSource.saved,
    'generated' => SuggestionSource.generated,
    _ => null,
  };
}

/// 제안 라벨 — 실행 가능성 표시(CONTEXT.md 글로서리).
enum SuggestionLabel {
  /// 부족 0
  ready('바로 가능'),

  /// 부족 1~3이 전부 대체재로 해소됨
  maybe('애매하지만 가능'),

  /// 그 외 부족 1~3
  buyOne('이것만 사면 가능');

  const SuggestionLabel(this.text);

  final String text;
}

/// 제안된 메뉴에 필요하지만 인식된 재료에는 없는 재료(CONTEXT.md 글로서리).
@immutable
class MissingIngredient {
  const MissingIngredient({required this.name, this.substitute});

  final String name;

  /// 대체재로 해소되면 그 이름 — "우유"가 부족한데 "두유"가 있으면 여기 "두유".
  final String? substitute;

  bool get resolvedBySubstitute => substitute != null;

  Map<String, Object?> toJson() => {
    'name': name,
    if (substitute != null) 'substitute': substitute,
  };

  factory MissingIngredient.fromJson(Map<String, Object?> json) =>
      MissingIngredient(
        name: json['name']! as String,
        substitute: json['substitute'] as String?,
      );

  @override
  bool operator ==(Object other) =>
      other is MissingIngredient &&
      other.name == name &&
      other.substitute == substitute;

  @override
  int get hashCode => Object.hash(name, substitute);
}

/// 부족 재료가 이만큼을 넘으면 제안이 아니라 장보기 목록이다 — 클라이언트에서 제외한다(스펙 #13).
const maxMissingIngredients = 3;

/// 한 번에 내놓는 제안 수 — "오늘 할 3개".
const maxSuggestions = 3;

@immutable
class Suggestion {
  const Suggestion({
    required this.menu,
    required this.source,
    required this.missing,
    required this.reason,
    this.recipeUrl,
    this.imageUrl,
  });

  final String menu;
  final SuggestionSource source;
  final List<MissingIngredient> missing;

  /// 근거 1줄.
  final String reason;

  /// 저장 레시피에서 온 제안만 원본 URL을 가진다 — "레시피 보기"가 이걸 새 탭으로 연다.
  final String? recipeUrl;

  /// 카드 히어로 음식 사진(og:image). 저장 제안만 URL이 있어 채워지고, AI 제안은 null이다.
  final String? imageUrl;

  /// og:image가 해석된 뒤 사진을 붙여 다시 만든다(게이트웨이 enrich 전용).
  Suggestion copyWith({String? imageUrl}) => Suggestion(
    menu: menu,
    source: source,
    missing: missing,
    reason: reason,
    recipeUrl: recipeUrl,
    imageUrl: imageUrl ?? this.imageUrl,
  );

  /// 부족 4개 이상은 제안에서 뺀다 — 카드 아래 투명성 줄에 집계만 남는다.
  bool get isActionable => missing.length <= maxMissingIngredients;

  /// 제안 라벨. **결정 순서가 고정이다**(스펙 #13) — 부족 0 → 전부 대체 해소 → 그 외.
  ///
  /// 순서를 바꾸면 같은 상황이 다른 라벨을 받는다. 라벨은 사용자가 실행 가능성을 한눈에
  /// 판단하는 유일한 신호라 흔들리면 안 된다.
  SuggestionLabel get label {
    if (missing.isEmpty) return SuggestionLabel.ready;
    if (missing.every((m) => m.resolvedBySubstitute)) {
      return SuggestionLabel.maybe;
    }
    return SuggestionLabel.buyOne;
  }

  Map<String, Object?> toJson() => {
    'menu': menu,
    'source': source.name,
    'missing': [for (final m in missing) m.toJson()],
    'reason': reason,
    if (recipeUrl != null) 'recipeUrl': recipeUrl,
    if (imageUrl != null) 'imageUrl': imageUrl,
  };

  @override
  bool operator ==(Object other) =>
      other is Suggestion &&
      other.menu == menu &&
      other.source == source &&
      listEquals(other.missing, missing) &&
      other.reason == reason &&
      other.recipeUrl == recipeUrl &&
      other.imageUrl == imageUrl;

  @override
  int get hashCode => Object.hash(
    menu,
    source,
    Object.hashAll(missing),
    reason,
    recipeUrl,
    imageUrl,
  );

  @override
  String toString() => 'Suggestion($menu, ${source.name}, ${label.name})';
}

/// LLM이 준 제안들을 화면에 올릴 목록으로 다듬은 결과.
@immutable
class SuggestionSelection {
  const SuggestionSelection({required this.shown, required this.excludedCount});

  final List<Suggestion> shown;

  /// 부족 4개 이상이라 제외된 메뉴 수 — 투명성 줄이 이걸 말한다.
  final int excludedCount;
}

/// 저장 레시피 매칭 우선, 모자라면 AI 제안으로 보충한다(스펙 #13). 합계 최대 3개.
///
/// 부족 4개 이상은 여기서 걸러지고, 몇 개가 걸렸는지는 투명성 줄로 나간다 —
/// 시스템이 뭘 걸렀는지 사용자가 알아야 한다.
SuggestionSelection selectSuggestions(List<Suggestion> all) {
  final actionable = [
    for (final s in all)
      if (s.isActionable) s,
  ];
  final excludedCount = all.length - actionable.length;

  final saved = [
    for (final s in actionable)
      if (s.source == SuggestionSource.saved) s,
  ];
  final generated = [
    for (final s in actionable)
      if (s.source == SuggestionSource.generated) s,
  ];

  return SuggestionSelection(
    shown: [...saved, ...generated].take(maxSuggestions).toList(),
    excludedCount: excludedCount,
  );
}
