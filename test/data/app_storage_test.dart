// 스토리지 모듈 유닛 — 이벤트 append·세션 복원의 영속 계약 검증
import 'package:cookmark/data/app_storage.dart';
import 'package:cookmark/models/app_event.dart';
import 'package:cookmark/models/ingredient.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AppStorage> openStorage([Map<String, Object> seed = const {}]) async {
    SharedPreferences.setMockInitialValues(seed);
    return AppStorage.open();
  }

  group('이벤트 로그 — 킬 기준 판정의 원시 데이터', () {
    test('append한 이벤트를 순서대로 되읽는다', () async {
      final s = await openStorage();
      await s.appendEvent(
        AppEvent(
          type: EventType.photoUploaded,
          at: DateTime.utc(2026, 7, 15, 1),
        ),
      );
      await s.appendEvent(
        AppEvent(
          type: EventType.recognitionCompleted,
          at: DateTime.utc(2026, 7, 15, 2),
          data: const {'latencyMs': 1900},
        ),
      );

      final events = s.events;
      expect(events, hasLength(2));
      expect(events.first.type, EventType.photoUploaded);
      expect(events.last.data['latencyMs'], 1900);
    });

    test('새 인스턴스로 다시 열어도 이벤트가 남아 있다 — 새로고침 후 유지', () async {
      final s = await openStorage();
      await s.appendEvent(
        AppEvent(type: EventType.photoUploaded, at: DateTime.utc(2026, 7, 15)),
      );

      final reopened = await AppStorage.open();
      expect(reopened.events, hasLength(1));
      expect(reopened.events.single.type, EventType.photoUploaded);
    });

    test('손상된 이벤트 JSON은 로그 전체를 죽이지 않는다', () async {
      final s = await openStorage({'cookmark.events': '{not json'});
      expect(s.events, isEmpty);

      await s.appendEvent(
        AppEvent(type: EventType.photoUploaded, at: DateTime.utc(2026, 7, 15)),
      );
      expect(s.events, hasLength(1));
    });
  });

  group('세션 복원 — 냉장고 앞에서 끊긴 흐름을 잇는다', () {
    test('저장한 재료 체크리스트가 체크 상태까지 복원된다', () async {
      final s = await openStorage();
      await s.saveSession(const [
        Ingredient(name: '대파', confidence: Confidence.high, checked: true),
        Ingredient(name: '트러플', confidence: Confidence.low, checked: false),
      ]);

      final reopened = await AppStorage.open();
      final restored = reopened.session;
      expect(restored, hasLength(2));
      expect(restored[0].name, '대파');
      expect(restored[0].checked, isTrue);
      expect(restored[1].confidence, Confidence.low);
      expect(restored[1].checked, isFalse);
    });

    test('저장된 세션이 없으면 빈 목록이다', () async {
      final s = await openStorage();
      expect(s.session, isEmpty);
    });

    test('세션을 비우면 복원되지 않는다', () async {
      final s = await openStorage();
      await s.saveSession(const [
        Ingredient(name: '대파', confidence: Confidence.high, checked: true),
      ]);
      await s.clearSession();

      expect((await AppStorage.open()).session, isEmpty);
    });
  });
}
