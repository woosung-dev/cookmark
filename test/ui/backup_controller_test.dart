// 백업 섹션의 동작 — export/import 이벤트와 7일 리마인더(#20).
import 'dart:convert';

import 'package:cookmark/data/storage.dart';
import 'package:cookmark/domain/app_event.dart';
import 'package:cookmark/domain/backup.dart';
import 'package:cookmark/domain/recipe.dart';
import 'package:cookmark/ui/backup_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Storage storage;
  var now = DateTime.utc(2026, 7, 15, 20);

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    storage = await Storage.open();
    now = DateTime.utc(2026, 7, 15, 20);
  });

  BackupController controller() => BackupController(storage, now: () => now);

  Iterable<AppEvent> backupEvents() =>
      storage.readEvents().where((e) => e.type == AppEventType.backup);

  Future<void> seed() async {
    await storage.writeRecipes([
      const Recipe(
        url: 'https://youtu.be/a',
        title: '김치찌개',
        ingredients: ['김치'],
      ),
    ]);
    await storage.appendEvent(
      AppEvent.photoUpload(at: DateTime.utc(2026, 7, 14), bytes: 1, width: 768),
    );
  }

  group('내보내기', () {
    test('레시피 북과 이벤트 로그가 한 파일로 나온다', () async {
      await seed();
      final json = jsonDecode(await controller().exportJson()) as Map;

      expect((json['recipes'] as List).single['title'], '김치찌개');
      expect((json['events'] as List), isNotEmpty);
    });

    test('내보내기가 이벤트로 남는다', () async {
      await seed();
      await controller().exportJson();

      final event = backupEvents().single;
      expect(event.data['direction'], 'export');
      expect(event.data['recipeCount'], 1);
      expect(event.data['eventCount'], 1);
    });

    test('내보내면 리마인더 시계가 리셋된다', () async {
      await seed();
      final c = controller();
      await c.exportJson();

      expect(storage.readLastBackupAt(), now);
      expect(c.needsBackup, isFalse);
    });
  });

  group('가져오기 — 미리보기를 거친다', () {
    Future<String> otherDeviceBackup() async {
      final other = BackupData(
        recipes: const [
          Recipe(url: 'https://youtu.be/b', title: '계란찜', ingredients: ['계란']),
        ],
        events: [
          AppEvent.photoUpload(
            at: DateTime.utc(2026, 7, 13),
            bytes: 1,
            width: 768,
          ),
        ],
        exportedAt: DateTime.utc(2026, 7, 14),
      );
      return jsonEncode(other.toJson());
    }

    test('미리보기만으로는 아무것도 바뀌지 않는다', () async {
      await seed();
      final c = controller()..previewImport(await otherDeviceBackup());

      expect(c.pendingMerge!.newRecipes.single.title, '계란찜');
      expect(storage.readRecipes(), hasLength(1), reason: '아직 반영 전');
      expect(backupEvents(), isEmpty);
    });

    test('확정해야 반영된다', () async {
      await seed();
      final c = controller()..previewImport(await otherDeviceBackup());
      await c.confirmImport();

      expect(storage.readRecipes().map((r) => r.title), ['김치찌개', '계란찜']);
      expect(c.pendingMerge, isNull);
    });

    test('가져오기가 병합 요약과 함께 이벤트로 남는다 (#20 AC)', () async {
      await seed();
      final c = controller()..previewImport(await otherDeviceBackup());
      await c.confirmImport();

      final event = backupEvents().single;
      expect(event.data['direction'], 'import');
      expect(event.data['newRecipes'], 1);
      expect(event.data['duplicateRecipes'], 0);
      expect(event.data['newEvents'], 1);
    });

    test('취소하면 미리보기가 사라지고 데이터는 그대로다', () async {
      await seed();
      final c = controller()..previewImport(await otherDeviceBackup());
      c.cancelImport();

      expect(c.pendingMerge, isNull);
      expect(storage.readRecipes(), hasLength(1));
    });

    test('자기 백업을 다시 가져와도 두 배가 되지 않는다 — 재가져오기 안전', () async {
      await seed();
      final c = controller();
      final mine = await c.exportJson();

      c.previewImport(mine);
      expect(c.pendingMerge!.changesNothing, isTrue);

      await c.confirmImport();
      expect(storage.readRecipes(), hasLength(1));
      // export 이벤트 1건은 백업 파일에 없던 것이라 남는다 — 그것 말고 늘어난 건 없다.
      expect(
        storage.readEvents().where((e) => e.type == AppEventType.photoUpload),
        hasLength(1),
      );
    });

    test('백업 파일이 아니면 읽을 수 있는 오류로 끝난다', () async {
      final c = controller()..previewImport('이건 JSON이 아니에요');

      expect(c.importError, '백업 파일이 아닌 것 같아요.');
      expect(c.pendingMerge, isNull);
    });

    test('JSON이지만 백업 모양이 아니어도 마찬가지다', () async {
      final c = controller()..previewImport('{"hello": "world"}');
      expect(c.importError, isNotNull);
    });

    test('미리보기 없이 확정하면 아무 일도 없다', () async {
      await seed();
      await controller().confirmImport();
      expect(backupEvents(), isEmpty);
    });
  });

  group('7일 리마인더', () {
    test('기록이 없으면 조르지 않는다', () {
      expect(controller().needsBackup, isFalse);
    });

    test('첫 기록으로부터 7일이 지나면 뜬다 — 설치만 한 사람을 첫날부터 조르지 않는다', () async {
      await storage.appendEvent(
        AppEvent.photoUpload(
          at: now.subtract(const Duration(days: 8)),
          bytes: 1,
          width: 768,
        ),
      );
      expect(controller().needsBackup, isTrue);
    });

    test('첫 기록이 이번 주면 아직 아니다', () async {
      await storage.appendEvent(
        AppEvent.photoUpload(
          at: now.subtract(const Duration(days: 2)),
          bytes: 1,
          width: 768,
        ),
      );
      expect(controller().needsBackup, isFalse);
    });

    test('마지막 백업으로부터 7일이 지나면 다시 뜬다', () async {
      await seed();
      await storage.writeLastBackupAt(now.subtract(const Duration(days: 8)));
      expect(controller().needsBackup, isTrue);
    });

    test('성적표에 수동 수정 수가 없다 (ADR-0004)', () async {
      for (var i = 0; i < 9; i++) {
        await storage.appendEvent(
          AppEvent.checklistEdit(
            at: now,
            kind: EditKind.uncheck,
            path: EditPath.row,
            name: '재료$i',
          ),
        );
      }
      final report = controller().weeklyReport;
      expect(report.copy, '이번 주 업로드 0회, 이거 했어요 0회 — 기록 저장하기');
    });
  });
}
