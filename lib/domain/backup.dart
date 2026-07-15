// 주간 백업 — 두 기기의 JSON을 모아 가구 단위로 분석하는 수집 지점(CONTEXT.md 글로서리).
//
// 브라우저 스토리지는 카톡 인앱 브라우저에서 유실될 수 있다. 이 파일이 유일한 보험이자,
// 파일럿 데이터를 파운더 손에 넣는 유일한 경로다(스펙 #13 — 서버측 수집은 Out of scope).
import 'package:flutter/foundation.dart';

import 'app_event.dart';
import 'recipe.dart';

/// export JSON 하나에 레시피 북과 이벤트 로그가 함께 담긴다(스펙 US 30).
@immutable
class BackupData {
  const BackupData({
    required this.recipes,
    required this.events,
    required this.exportedAt,
  });

  final List<Recipe> recipes;
  final List<AppEvent> events;
  final DateTime exportedAt;

  Map<String, Object?> toJson() => {
    'version': 1,
    'exportedAt': exportedAt.toUtc().toIso8601String(),
    'recipes': [for (final r in recipes) r.toJson()],
    'events': [for (final e in events) e.toJson()],
  };

  factory BackupData.fromJson(Map<String, Object?> json) => BackupData(
    exportedAt: DateTime.parse(json['exportedAt']! as String),
    recipes: [
      for (final r in json['recipes'] as List<Object?>? ?? const [])
        Recipe.fromJson((r! as Map).cast<String, Object?>()),
    ],
    events: [
      for (final e in json['events'] as List<Object?>? ?? const [])
        AppEvent.fromJson((e! as Map).cast<String, Object?>()),
    ],
  );
}

/// 가져오기를 확정하기 전에 보여줄 요약(C 이식, G1 #8) — 무엇이 들어오고 무엇이 겹치는지.
@immutable
class MergePreview {
  const MergePreview({
    required this.newRecipes,
    required this.duplicateRecipeCount,
    required this.newEventCount,
    required this.duplicateEventCount,
    required this.mergedRecipes,
    required this.mergedEvents,
  });

  /// 새로 들어올 레시피들 — 미리보기에 이름을 보여준다.
  final List<Recipe> newRecipes;

  /// URL이 겹쳐 건너뛴 수.
  final int duplicateRecipeCount;

  final int newEventCount;
  final int duplicateEventCount;

  final List<Recipe> mergedRecipes;
  final List<AppEvent> mergedEvents;

  bool get changesNothing => newRecipes.isEmpty && newEventCount == 0;

  /// 이벤트에 남길 병합 요약.
  Map<String, Object?> toSummary() => {
    'newRecipes': newRecipes.length,
    'duplicateRecipes': duplicateRecipeCount,
    'newEvents': newEventCount,
    'duplicateEvents': duplicateEventCount,
  };
}

/// 이벤트의 동일성 — 같은 시각에 난 같은 종류의 일은 같은 일로 본다.
///
/// 재가져오기(자기 백업 복원)에서 로그가 두 배가 되지 않게 하는 장치다.
String _eventKey(AppEvent e) =>
    '${e.type.name}@${e.at.toUtc().toIso8601String()}@${e.data['name'] ?? e.data['menu'] ?? e.data['url'] ?? ''}';

/// 지금 있는 것과 들어온 것을 합친다 — 레시피는 URL로, 이벤트는 시각+종류로 중복을 뺀다.
///
/// 겹치면 **지금 것을 남긴다**. 들어온 백업이 오래된 것일 수 있고, 내 기기의 기록이 더 정확하다.
MergePreview previewMerge({
  required BackupData current,
  required BackupData incoming,
}) {
  final existingUrls = {for (final r in current.recipes) r.url};
  final newRecipes = <Recipe>[];
  var duplicateRecipeCount = 0;
  for (final recipe in incoming.recipes) {
    if (existingUrls.contains(recipe.url)) {
      duplicateRecipeCount++;
    } else {
      existingUrls.add(recipe.url);
      newRecipes.add(recipe);
    }
  }

  final existingEventKeys = {for (final e in current.events) _eventKey(e)};
  final newEvents = <AppEvent>[];
  var duplicateEventCount = 0;
  for (final event in incoming.events) {
    if (existingEventKeys.contains(_eventKey(event))) {
      duplicateEventCount++;
    } else {
      existingEventKeys.add(_eventKey(event));
      newEvents.add(event);
    }
  }

  // 합친 이벤트는 시간순으로 다시 세운다 — 분석이 타임스탬프에서 업로드 세션을 파생하므로.
  final mergedEvents = [...current.events, ...newEvents]
    ..sort((a, b) => a.at.compareTo(b.at));

  return MergePreview(
    newRecipes: newRecipes,
    duplicateRecipeCount: duplicateRecipeCount,
    newEventCount: newEvents.length,
    duplicateEventCount: duplicateEventCount,
    mergedRecipes: [...current.recipes, ...newRecipes],
    mergedEvents: mergedEvents,
  );
}

/// 백업을 권하는 주기 — 일요일 저녁 루틴(CONTEXT.md "주간 백업")에 맞춘다.
const backupReminderAfter = Duration(days: 7);

/// 주간 성적표 카피의 숫자(C 이식, G1 #8).
///
/// **수동 수정 수는 절대 들어오지 않는다.** 배우자에게 계측의 존재를 알리지 않는
/// 단일맹검(ADR-0004)이 여기서 깨지면 P2 킬 기준 측정이 통째로 오염된다.
@immutable
class WeeklyReport {
  const WeeklyReport({required this.uploads, required this.cooked});

  final int uploads;
  final int cooked;

  String get copy => '이번 주 업로드 $uploads회, 이거 했어요 $cooked회 — 기록 저장하기';
}

WeeklyReport weeklyReportFrom(List<AppEvent> events, DateTime now) {
  final since = now.subtract(const Duration(days: 7));
  var uploads = 0;
  var cooked = 0;
  for (final event in events) {
    if (event.at.isBefore(since)) continue;
    if (event.type == AppEventType.photoUpload) uploads++;
    if (event.type == AppEventType.cooked) cooked++;
  }
  return WeeklyReport(uploads: uploads, cooked: cooked);
}
