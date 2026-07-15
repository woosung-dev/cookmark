// 이벤트 로그 모델 유닛 — export JSON 계약과 라운드트립 검증
import 'package:cookmark/models/app_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final at = DateTime.utc(2026, 7, 15, 19, 30);

  group('이벤트 JSON 라운드트립 — export가 정본 수집 지점이다', () {
    test('사진 업로드 이벤트가 타임스탬프와 함께 직렬화된다', () {
      final e = AppEvent(type: EventType.photoUploaded, at: at);
      final back = AppEvent.fromJson(e.toJson());
      expect(back.type, EventType.photoUploaded);
      expect(back.at, at);
    });

    test('인식 완료 이벤트가 지연·토큰·추정 원가를 보존한다', () {
      final e = AppEvent(
        type: EventType.recognitionCompleted,
        at: at,
        data: const {
          'latencyMs': 1900,
          'inputTokens': 1064,
          'outputTokens': 48,
          'estimatedCostUsd': 0.0011,
          'ingredientCount': 5,
        },
      );
      final back = AppEvent.fromJson(e.toJson());
      expect(back.data['latencyMs'], 1900);
      expect(back.data['inputTokens'], 1064);
      expect(back.data['outputTokens'], 48);
      expect(back.data['estimatedCostUsd'], 0.0011);
    });

    test('모르는 type 문자열은 예외 없이 unknown으로 읽힌다 — 백업 재가져오기 방어', () {
      final back = AppEvent.fromJson({
        'type': 'someFutureEvent',
        'at': at.toIso8601String(),
        'data': <String, dynamic>{},
      });
      expect(back.type, EventType.unknown);
    });

    test('타임스탬프는 UTC ISO-8601로 직렬화된다 — 두 기기 로그 합산의 전제', () {
      final e = AppEvent(type: EventType.photoUploaded, at: at);
      expect(e.toJson()['at'], '2026-07-15T19:30:00.000Z');
    });

    test('로컬 시각으로 만든 이벤트도 UTC로 저장된다', () {
      final local = DateTime(2026, 7, 15, 19, 30);
      final e = AppEvent(type: EventType.photoUploaded, at: local);
      final back = AppEvent.fromJson(e.toJson());
      expect(back.at.isUtc, isTrue);
      expect(back.at, local.toUtc());
    });
  });

  group('이벤트 카탈로그 — 스펙 #13의 12종', () {
    test('#14 구간에서 쓰는 유형이 정의돼 있다', () {
      expect(EventType.photoUploaded.wireName, 'photo_uploaded');
      expect(EventType.recognitionCompleted.wireName, 'recognition_completed');
      expect(EventType.errorShown.wireName, 'error_shown');
    });
  });
}
