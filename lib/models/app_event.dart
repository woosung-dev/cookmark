// 이벤트 로그 모델 — 킬 기준·성공 지표를 판정할 원시 데이터의 단위(스펙 #13 카탈로그 12종)
import 'package:flutter/foundation.dart';

/// 스펙 #13의 이벤트 카탈로그 12종. `wireName`이 export JSON의 계약이므로
/// 값을 바꾸면 이미 수집된 백업과 비교 불가가 된다 — 파일럿 중 변경 금지.
enum EventType {
  photoUploaded('photo_uploaded'),
  recognitionCompleted('recognition_completed'),
  checklistEdited('checklist_edited'),
  matchingCompleted('matching_completed'),
  suggestionsShown('suggestions_shown'),
  suggestionSelected('suggestion_selected'),
  cooked('cooked'),
  cookUndone('cook_undone'),
  rematchRequested('rematch_requested'),
  recipeBookChanged('recipe_book_changed'),
  backupPerformed('backup_performed'),
  errorShown('error_shown'),

  /// 카탈로그에 없는 값을 읽었을 때. 백업 재가져오기가 예외로 죽지 않게 한다.
  unknown('unknown');

  const EventType(this.wireName);

  final String wireName;

  static EventType parse(String? raw) => EventType.values.firstWhere(
    (t) => t.wireName == raw,
    orElse: () => EventType.unknown,
  );
}

/// 이벤트 1건. 모든 이벤트에 타임스탬프가 붙고, 유형별 상세는 [data]에 담는다.
@immutable
class AppEvent {
  AppEvent({required this.type, required DateTime at, this.data = const {}})
    : at = at.toUtc();

  factory AppEvent.fromJson(Map<String, dynamic> json) => AppEvent(
    type: EventType.parse(json['type'] as String?),
    at: DateTime.parse(json['at'] as String),
    data: Map<String, dynamic>.from(json['data'] as Map? ?? const {}),
  );

  final EventType type;

  /// 항상 UTC. 두 기기(파운더·배우자)의 로그를 가구 단위로 합산하려면 필수다.
  final DateTime at;
  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() => {
    'type': type.wireName,
    'at': at.toIso8601String(),
    'data': data,
  };
}
