// 이벤트 로그의 단위 — 스펙 #13의 이벤트 카탈로그 12종. 킬 기준·성공 지표를 판정할 원시 데이터다.
import 'package:flutter/foundation.dart';

import '../llm/llm_gateway.dart';

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
  /// **수동 수정 산식에 넣을지는 미결이다.** ADR-0003이 열거한 4종(해제·재체크·추가·치환)에
  /// 이 조작은 없지만, 같은 ADR의 취지문은 "사용자 손이 간 횟수 전부가 계측 대상"이라고 한다.
  /// 판정을 유보한 채 별도 kind로 남긴다 — 그래야 분석 단계에서 어느 쪽 산식이든 재산할 수 있다.
  vagueDismiss;

  /// ADR-0003이 열거한 수동 수정 산식의 대상. [vagueDismiss]는 미결이라 빠져 있다.
  bool get countsAsManualEdit => this != EditKind.vagueDismiss;
}

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

  factory AppEvent.fromJson(Map<String, Object?> json) {
    final rest = Map<String, Object?>.from(json)
      ..remove('type')
      ..remove('at');
    return AppEvent(
      type: AppEventType.parse(json['type']! as String)!,
      at: DateTime.parse(json['at']! as String),
      data: rest,
    );
  }

  @override
  String toString() => 'AppEvent(${type.name}, $at, $data)';
}
