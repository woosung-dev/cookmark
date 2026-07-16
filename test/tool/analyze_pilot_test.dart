// 판정 CLI(tool/analyze_pilot.dart)의 계약 드리프트 가드 + 순수 로직 유닛.
import 'dart:convert';

import 'package:cookmark/domain/app_event.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../tool/analyze_pilot.dart';

/// 이벤트 와이어 맵 생성기 — AppEvent.toJson 의 평평한 형태({type, at, ...data}).
Map<String, Object?> ev(
  String type,
  DateTime at, [
  Map<String, Object?> data = const {},
]) => {'type': type, 'at': at.toUtc().toIso8601String(), ...data};

String backupJson(List<Map<String, Object?>> events) => jsonEncode({
  'version': 1,
  'exportedAt': DateTime.utc(2026, 8, 5).toIso8601String(),
  'recipes': <Object?>[],
  'events': events,
});

final start = DateTime.parse('2026-07-22T18:00:00+09:00'); // = 09:00Z
DateTime day(int d, {int h = 1, int m = 0}) =>
    start.add(Duration(days: d, hours: h, minutes: m));

void main() {
  group('계약 드리프트 가드 — 툴이 아는 이름 == 실제 enum', () {
    test('이벤트 카탈로그 12종이 AppEventType 과 정확히 일치', () {
      final real = AppEventType.values.map((e) => e.name).toSet();
      expect(knownEventTypes, equals(real));
    });

    test('체크리스트 조작 유형이 EditKind 과 정확히 일치', () {
      final real = EditKind.values.map((e) => e.name).toSet();
      expect(knownEditKinds, equals(real));
    });
  });

  group('countSessions — 30분 윈도', () {
    test('빈 목록은 0', () {
      expect(countSessions([], const Duration(minutes: 30)), 0);
    });

    test('30분 이내는 한 세션', () {
      final t = day(0);
      expect(
        countSessions([
          t,
          t.add(const Duration(minutes: 20)),
        ], const Duration(minutes: 30)),
        1,
      );
    });

    test('30분 초과 간격은 새 세션', () {
      final t = day(0);
      expect(
        countSessions([
          t,
          t.add(const Duration(minutes: 40)),
        ], const Duration(minutes: 30)),
        2,
      );
    });
  });

  group('weekIndexOf — D0 앵커', () {
    test('D0 이전은 null', () {
      expect(
        weekIndexOf(start.subtract(const Duration(hours: 1)), start),
        null,
      );
    });

    test('0~6일은 주 0, 7~13일은 주 1, 14일은 주 2', () {
      expect(weekIndexOf(day(0), start), 0);
      expect(weekIndexOf(day(6), start), 0);
      expect(weekIndexOf(day(7), start), 1);
      expect(weekIndexOf(day(13), start), 1);
      expect(weekIndexOf(day(14), start), 2);
    });
  });

  group('aggregate + P2 산식', () {
    // 한 주에 세션 2개(40분 간격 업로드 2개) + 수동 수정 events 를 만든다.
    List<Map<String, Object?>> weekWith({
      required int weekDay,
      required List<String> editKinds,
    }) => [
      ev('photoUpload', day(weekDay, h: 1)),
      ev('photoUpload', day(weekDay, h: 1, m: 40)), // gap 40 → 새 세션
      for (var i = 0; i < editKinds.length; i++)
        ev('checklistEdit', day(weekDay, h: 1, m: 2 + i), {
          'kind': editKinds[i],
          'path': 'row',
          'name': '재료$i',
        }),
    ];

    test('사진당 수동 수정 = 수정합/세션수, 임계 초과면 atRisk', () {
      final events = readBackupEvents(
        backupJson(weekWith(weekDay: 0, editKinds: List.filled(12, 'uncheck'))),
      ).toList();
      final r = aggregate(
        label: 'dev',
        events: events,
        start: start,
        gap: const Duration(minutes: 30),
      );
      final w0 = r.weeks[0]!;
      expect(w0.sessions, 2);
      expect(w0.editsTotal, 12);
      expect(w0.editsPerSession, 6.0); // 12/2 > 5
      expect(w0.atRisk, true);
    });

    test('제외 산식은 recheck·vagueDismiss 를 뺀다', () {
      final events = readBackupEvents(
        backupJson(
          weekWith(
            weekDay: 0,
            editKinds: [
              'uncheck', 'uncheck', 'recheck', 'vagueDismiss', // 4건 중 2건 제외
            ],
          ),
        ),
      ).toList();
      final w0 = aggregate(
        label: 'dev',
        events: events,
        start: start,
        gap: const Duration(minutes: 30),
      ).weeks[0]!;
      expect(w0.editsTotal, 4);
      expect(w0.editsStrict, 2);
      expect(w0.editsPerSession, 2.0); // 4/2
      expect(w0.editsPerSessionStrict, 1.0); // 2/2
    });

    test('세션 0이면 사진당 수정은 정의 불가(null), atRisk 아님', () {
      final events = readBackupEvents(
        backupJson([
          ev('checklistEdit', day(0), {
            'kind': 'add',
            'path': 'typing',
            'name': 'x',
          }),
        ]),
      );
      final w0 = aggregate(
        label: 'dev',
        events: events,
        start: start,
        gap: const Duration(minutes: 30),
      ).weeks[0]!;
      expect(w0.sessions, 0);
      expect(w0.editsPerSession, null);
      expect(w0.atRisk, false);
    });

    test('P2 킬은 위험 주가 2주 연속일 때만 발화', () {
      final risky = [
        ...weekWith(weekDay: 0, editKinds: List.filled(12, 'uncheck')),
        ...weekWith(weekDay: 7, editKinds: List.filled(12, 'uncheck')),
      ];
      final household = mergeHousehold([
        aggregate(
          label: 'dev',
          events: readBackupEvents(backupJson(risky)),
          start: start,
          gap: const Duration(minutes: 30),
        ),
      ]);
      expect(p2KillFired(household), true);
    });

    test('한 주만 위험이면 킬 미발화', () {
      final oneRisky = [
        ...weekWith(weekDay: 0, editKinds: List.filled(12, 'uncheck')), // 위험
        ...weekWith(
          weekDay: 7,
          editKinds: List.filled(2, 'uncheck'),
        ), // 2/2=1 안전
      ];
      final household = mergeHousehold([
        aggregate(
          label: 'dev',
          events: readBackupEvents(backupJson(oneRisky)),
          start: start,
          gap: const Duration(minutes: 30),
        ),
      ]);
      expect(p2KillFired(household), false);
    });
  });

  group('cooked stale 분리 · preD0 제외 · 자발', () {
    test('cooked 는 stale 여부로 나뉜다', () {
      final events = readBackupEvents(
        backupJson([
          ev('cooked', day(0), {'menu': 'a', 'stale': false}),
          ev('cooked', day(0), {'menu': 'b', 'stale': true}),
        ]),
      );
      final w0 = aggregate(
        label: 'dev',
        events: events,
        start: start,
        gap: const Duration(minutes: 30),
      ).weeks[0]!;
      expect(w0.cookedFresh, 1);
      expect(w0.cookedStale, 1);
    });

    test('D0 이전 이벤트는 주에서 빠지고 preD0Events 로 센다', () {
      final events = readBackupEvents(
        backupJson([
          ev('photoUpload', start.subtract(const Duration(days: 1))),
          ev('photoUpload', day(0)),
        ]),
      );
      final r = aggregate(
        label: 'dev',
        events: events,
        start: start,
        gap: const Duration(minutes: 30),
      );
      expect(r.preD0Events, 1);
      expect(r.weeks[0]!.photoUploads, 1);
    });

    test('자발 사용 = 주 3세션 이상', () {
      // 40분 간격 업로드 3개 → 3세션
      final events = readBackupEvents(
        backupJson([
          for (var i = 0; i < 3; i++)
            ev('photoUpload', day(0, h: 1, m: 40 * i)),
        ]),
      );
      final w0 = aggregate(
        label: 'dev',
        events: events,
        start: start,
        gap: const Duration(minutes: 30),
      ).weeks[0]!;
      expect(w0.sessions, 3);
      expect(w0.voluntary, true);
    });
  });
}
