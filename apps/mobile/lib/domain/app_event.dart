// 이벤트 로그의 단위 — 스펙 #13의 이벤트 카탈로그 12종. 킬 기준·성공 지표를 판정할 원시 데이터다.
import 'package:flutter/foundation.dart';

import '../llm/llm_gateway.dart';
import 'suggestion.dart';

/// 이벤트 카탈로그 12종(스펙 #13 계측). export JSON의 `type` 값이 곧 이 이름이다.
///
/// 이 열거형은 분석의 계약이다 — 값을 지우거나 이름을 바꾸면 이미 수집된 백업 JSON이 해석 불가가 된다.
enum AppEventType {
  /// ① 사진 업로드
  photoUpload,

  /// ② 인식 완료 (지연·토큰·원가)
  recognitionDone,

  /// ③ 체크리스트 조작 (유형·경로) — 수동 수정 계측의 원본(ADR-0003)
  checklistEdit,

  /// ④ 매칭 완료 (지연·토큰·원가·제외 수)
  matchingDone,

  /// ⑤ 제안 노출 (라벨·출처 분포·stale)
  suggestionsShown,

  /// ⑥ 제안 선택 ("레시피 보기")
  suggestionOpened,

  /// ⑦ 이거 했어요
  cooked,

  /// ⑧ 실행취소
  cookedUndo,

  /// ⑨ 다시 제안
  rematch,

  /// ⑩ 레시피 북 변경
  recipeBookChanged,

  /// ⑪ 백업 export/import (병합 요약) — 방향은 `direction` 필드로 구분한다
  backup,

  /// ⑫ 오류 표시 (유형)
  errorShown;

  static AppEventType? parse(String raw) {
    for (final t in AppEventType.values) {
      if (t.name == raw) return t;
    }
    return null;
  }
}

/// 체크리스트 조작의 유형. low 환각을 그냥 둔 것만 0이다(ADR-0003).
enum EditKind {
  /// 오인식 제거
  uncheck,

  /// low 항목 복원
  recheck,

  /// 직접 추가
  add,

  /// 뭉뚱그림 치환 (1시퀀스 = 1회)
  substitute,

  /// 뭉뚱그림 오탐 복귀 — 칩을 탭 1회로 일반 항목으로 되돌린다(ADR-0002).
  ///
  /// 이것도 수동 수정 1회다(ADR-0003, #28에서 확정) — 원인이 모델 인식이든 클라이언트
  /// 휴리스틱이든 사용자에겐 탭이 마찰이다. 별도 kind로 남기는 건 제외 산식을 분석 단계에서
  /// 재산할 수 있게 하려는 것이지, 계측에서 빼려는 게 아니다.
  vagueDismiss,
}

/// 레시피 북에 무슨 일이 일어났는지.
///
/// [reextract]는 추출이 실패해 재료 0개로 저장된 레시피에 사용자가 "다시 시도"를 눌러
/// **추출만** 다시 돌린 것이다 — 레시피 북의 구성원은 바뀌지 않는다. [add]로 뭉뚱그리지
/// 않는 이유: 분석이 URL 하나를 두 번 담은 것으로 세면 질문 2의 분모가 부푼다.
/// 카탈로그(12종)는 그대로다 — 이건 이벤트 ⑩의 데이터 필드 값이지 새 이벤트 유형이 아니다.
enum RecipeBookAction { add, remove, reextract, restore }

/// 백업이 나간 건지 들어온 건지 — 카탈로그 ⑪은 하나이고 방향으로 갈린다.
enum BackupDirection { export, import }

/// 조작이 어느 경로로 들어왔는지 — 분석 단계에서 대안 산식을 재산할 해상도(ADR-0003).
enum EditPath {
  /// 행 전체 탭 토글
  row,

  /// 하단 고정 추가 바
  typing,

  /// "자주 쓰는 재료" 칩
  frequentChip,

  /// 레시피 북 미인식 칩
  recipeBookChip,

  /// 뭉뚱그림 칩의 인라인 치환
  vagueChip,
}

/// 이벤트 1건. `data`는 유형별 필드이고, 생성자가 그 스키마를 강제한다.
@immutable
class AppEvent {
  const AppEvent({required this.type, required this.at, this.data = const {}});

  /// ① 사진 업로드
  AppEvent.photoUpload({
    required this.at,
    required int bytes,
    required int width,
  }) : type = AppEventType.photoUpload,
       data = {'bytes': bytes, 'width': width};

  /// ② 인식 완료 — 지연·토큰·원가. 토큰은 뭉치지 않고 T1 #6이 지정한 필드 그대로 남긴다.
  AppEvent.recognitionDone({
    required this.at,
    required Duration latency,
    required LlmUsage usage,
    required int count,
  }) : type = AppEventType.recognitionDone,
       data = {
         'latencyMs': latency.inMilliseconds,
         ...usage.toJson(),
         'count': count,
       };

  /// ③ 체크리스트 조작 — 유형·경로를 반드시 분리 기록한다(ADR-0003).
  AppEvent.checklistEdit({
    required this.at,
    required EditKind kind,
    required EditPath path,
    required String name,
    Map<String, Object?> extra = const {},
  }) : type = AppEventType.checklistEdit,
       data = {'kind': kind.name, 'path': path.name, 'name': name, ...extra};

  /// ④ 매칭 완료 — 지연·토큰·원가·제외 수.
  AppEvent.matchingDone({
    required this.at,
    required Duration latency,
    required LlmUsage usage,
    required int shownCount,
    required int excludedCount,
  }) : type = AppEventType.matchingDone,
       data = {
         'latencyMs': latency.inMilliseconds,
         ...usage.toJson(),
         'shownCount': shownCount,
         'excludedCount': excludedCount,
       };

  /// ⑤ 제안 노출 — 라벨·출처 분포.
  ///
  /// [stale]은 보통 거짓이지만 늘 그렇지는 않다 — 매칭이 날아가는 동안 재료를 손대면
  /// 제안은 뜨는 순간부터 낡은 재고의 답이다. 로그가 그걸 거짓으로 적으면 성공 지표 2가 오염된다.
  AppEvent.suggestionsShown({
    required this.at,
    required List<Suggestion> suggestions,
    required bool stale,
  }) : type = AppEventType.suggestionsShown,
       data = {
         'labels': [for (final s in suggestions) s.label.name],
         'sources': [for (final s in suggestions) s.source.name],
         'menus': [for (final s in suggestions) s.menu],
         'stale': stale,
       };

  /// ⑥ 제안 선택 — "레시피 보기"로 원본을 열었다. 성공 지표의 앞단이다.
  AppEvent.suggestionOpened({
    required this.at,
    required Suggestion suggestion,
    required bool stale,
  }) : type = AppEventType.suggestionOpened,
       data = {
         'menu': suggestion.menu,
         'source': suggestion.source.name,
         'label': suggestion.label.name,
         'stale': stale,
         if (suggestion.recipeUrl != null) 'url': suggestion.recipeUrl,
       };

  /// ⑦ 이거 했어요 — 성공 지표 2(행동 변화)의 판정 장치.
  ///
  /// [stale]이 참이면 낡은 재고로 뽑힌 제안에서 눌린 것이다. 성공 지표 2 집계에서
  /// 분리할 수 있어야 한다(ADR-0001) — 그래서 플래그를 이벤트에 박아둔다.
  AppEvent.cooked({
    required this.at,
    required Suggestion suggestion,
    required bool stale,
  }) : type = AppEventType.cooked,
       data = {
         'menu': suggestion.menu,
         'source': suggestion.source.name,
         'label': suggestion.label.name,
         'stale': stale,
       };

  /// ⑧ 실행취소 — 5초 안에 되돌렸다. 취소도 데이터다.
  AppEvent.cookedUndo({
    required this.at,
    required Suggestion suggestion,
    required bool stale,
  }) : type = AppEventType.cookedUndo,
       data = {'menu': suggestion.menu, 'stale': stale};

  /// ⑨ 다시 제안 — 재료를 손본 뒤 낡은 제안을 갱신했다.
  AppEvent.rematch({required this.at, required int previousCount})
    : type = AppEventType.rematch,
      data = {'previousCount': previousCount};

  /// ⑩ 레시피 북 변경 — 질문 2(저장 레시피가 선택을 바꾸는가)의 분모가 여기서 자란다.
  AppEvent.recipeBookChanged({
    required this.at,
    required RecipeBookAction action,
    required String url,
    required String title,
    required int ingredientCount,
    LlmUsage? usage,
  }) : type = AppEventType.recipeBookChanged,
       data = {
         'action': action.name,
         'url': url,
         'title': title,
         'ingredientCount': ingredientCount,
         if (usage != null) ...usage.toJson(),
       };

  /// ⑪ 백업 export/import — 방향과 병합 요약.
  AppEvent.backup({
    required this.at,
    required BackupDirection direction,
    required int recipeCount,
    required int eventCount,
    Map<String, Object?> mergeSummary = const {},
  }) : type = AppEventType.backup,
       data = {
         'direction': direction.name,
         'recipeCount': recipeCount,
         'eventCount': eventCount,
         ...mergeSummary,
       };

  /// ⑫ 오류 표시
  AppEvent.errorShown({
    required this.at,
    required String kind,
    required String stage,
  }) : type = AppEventType.errorShown,
       data = {'kind': kind, 'stage': stage};

  final AppEventType type;
  final DateTime at;
  final Map<String, Object?> data;

  Map<String, Object?> toJson() => {
    'type': type.name,
    'at': at.toUtc().toIso8601String(),
    ...data,
  };

  /// 모르는 유형이면 null — 앞선 버전이 쓴 이벤트 1건이 로그 전체를 막으면 안 된다.
  /// [AppEventType.parse]와 같은 계약이다(모르면 null).
  static AppEvent? parse(Map<String, Object?> json) {
    final type = AppEventType.parse(json['type']! as String);
    if (type == null) return null;
    final rest = Map<String, Object?>.from(json)
      ..remove('type')
      ..remove('at');
    return AppEvent(
      type: type,
      at: DateTime.parse(json['at']! as String),
      data: rest,
    );
  }

  @override
  String toString() => 'AppEvent(${type.name}, $at, $data)';
}
