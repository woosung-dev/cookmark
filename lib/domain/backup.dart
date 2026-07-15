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
    required this.ignoredEventCount,
    required this.mergedRecipes,
  });

  /// 새로 들어올 레시피들 — 미리보기에 이름을 보여준다.
  final List<Recipe> newRecipes;

  /// URL이 겹쳐 건너뛴 수.
  final int duplicateRecipeCount;

  /// 백업 파일에 들어 있었지만 **가져오지 않은** 이벤트 수 — 아래 주석 참조.
  final int ignoredEventCount;

  final List<Recipe> mergedRecipes;

  bool get changesNothing => newRecipes.isEmpty;

  /// 이벤트에 남길 병합 요약.
  Map<String, Object?> toSummary() => {
    'newRecipes': newRecipes.length,
    'duplicateRecipes': duplicateRecipeCount,
    'ignoredEvents': ignoredEventCount,
  };
}

/// 들어온 백업에서 **레시피만** 가져온다. 이벤트 로그는 건드리지 않는다.
///
/// 스펙 US 25는 "URL 중복 제거 병합"으로 레시피만 말하고, 그럴 만한 이유가 있다 —
/// 배우자 기기 시딩(이 기능의 주 용도)에서 남의 이벤트가 내 로그에 섞이면,
/// 다음 주 export가 그걸 되뱉어 **US 30의 "백업 파일 2개로 가구 단위 분석"에서
/// 인별 귀속이 깨진다.** 두 파일이 서로를 머금으면 누가 몇 번 했는지 셀 수 없다.
///
/// 이벤트 유실이 걱정될 수 있지만, 주간 백업의 정의(CONTEXT.md)상 보험은 "파운더 로컬 폴더에
/// 보관된 파일"이지 "기기 복원"이 아니다. 기록은 이미 안전하다.
///
/// 레시피가 겹치면 **지금 것을 남긴다** — 들어온 백업이 오래된 것일 수 있고 내 기기 기록이 더 정확하다.
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

  return MergePreview(
    newRecipes: newRecipes,
    duplicateRecipeCount: duplicateRecipeCount,
    ignoredEventCount: incoming.events.length,
    mergedRecipes: [...current.recipes, ...newRecipes],
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
