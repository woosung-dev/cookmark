// 백업 서버 모드(#121) — 가져오기 확정이 서버 bulk를 거치고, export는 미러+로컬 이벤트 그대로.
import 'dart:convert';

import 'package:cookmark/data/server_recipe_repository.dart';
import 'package:cookmark/data/storage.dart';
import 'package:cookmark/domain/app_event.dart';
import 'package:cookmark/domain/backup.dart';
import 'package:cookmark/domain/recipe.dart';
import 'package:cookmark/ui/backup_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import '../support/fake_server_recipe_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Storage storage;
  late FakeServerRecipeRepository server;
  var now = DateTime.utc(2026, 7, 18, 20);

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    storage = await Storage.open();
    now = DateTime.utc(2026, 7, 18, 20);
    server = FakeServerRecipeRepository(
      seed: const [
        Recipe(url: 'https://youtu.be/a', title: '김치찌개', ingredients: ['김치']),
      ],
    );
    // 하이드레이트된 상태를 흉내 낸다 — 미러 = 서버 목록.
    await storage.writeRecipes(server.recipes);
  });

  BackupController controller() =>
      BackupController(storage, now: () => now, server: server);

  Iterable<AppEvent> backupEvents() =>
      storage.readEvents().where((e) => e.type == AppEventType.backup);

  /// 다른 기기 백업 — 겹치는 a + 새 b + 남의 이벤트 1건.
  String otherDeviceBackup() => jsonEncode(
    BackupData(
      recipes: const [
        Recipe(url: 'https://youtu.be/a', title: '김치찌개', ingredients: ['김치']),
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
    ).toJson(),
  );

  test('확정하면 newRecipes만 서버 bulk로 간다 — dedup 책임은 클라이언트다', () async {
    final c = controller()..previewImport(otherDeviceBackup());
    await c.confirmImport();

    expect(server.importBulkCallCount, 1);
    expect(server.lastImportBulk!.map((r) => r.url), ['https://youtu.be/b']);
  });

  test('성공하면 fetchAll 재수화로 미러가 서버 정본이 되고 이벤트 1건이 남는다', () async {
    final c = controller()..previewImport(otherDeviceBackup());
    await c.confirmImport();

    // 서버 삽입순 + 서버 발급 id 그대로.
    expect(storage.readRecipes().map((r) => r.url), [
      'https://youtu.be/a',
      'https://youtu.be/b',
    ]);
    expect(storage.readRecipes().last.id, isNotNull);
    expect(c.pendingMerge, isNull);

    final event = backupEvents().single;
    expect(event.data['direction'], 'import');
    expect(event.data['recipeCount'], 2);
    expect(event.data['newRecipes'], 1);
    expect(event.data['duplicateRecipes'], 1);
  });

  test('서버가 죽으면 미러·pendingMerge·이벤트 전부 불변 + importError', () async {
    final c = controller()..previewImport(otherDeviceBackup());
    server.failure = const RecipeApiFailure(RecipeApiFailureKind.unavailable);

    await c.confirmImport();

    expect(c.importError, '가져오기에 실패했어요 — 서버에 저장되지 않았어요.');
    expect(c.pendingMerge, isNotNull, reason: '다시 확정할 수 있어야 한다');
    expect(storage.readRecipes(), hasLength(1), reason: '미러 불변');
    expect(backupEvents(), isEmpty);
  });

  test('changesNothing이면 서버 bulk를 부르지 않는다 — 기존 흐름 그대로', () async {
    // 자기 백업 재가져오기 — 새로 들어올 게 없다.
    final mine = await controller().exportJson();
    final c = controller()..previewImport(mine);
    expect(c.pendingMerge!.changesNothing, isTrue, reason: '전제');

    await c.confirmImport();

    expect(server.importBulkCallCount, 0);
    expect(storage.readRecipes(), hasLength(1));
    expect(backupEvents().map((e) => e.data['direction']), [
      'export',
      'import',
    ]);
  });

  test('export는 미러 + 로컬 이벤트 그대로 — 서버를 부르지 않는다', () async {
    await storage.appendEvent(
      AppEvent.photoUpload(at: now, bytes: 1, width: 768),
    );
    final fetchesBefore = server.fetchAllCallCount;

    final json =
        jsonDecode(await controller().exportJson()) as Map<String, Object?>;

    expect(server.fetchAllCallCount, fetchesBefore, reason: 'export는 로컬 읽기다');
    expect(
      (json['recipes'] as List).cast<Map<String, Object?>>().single['url'],
      'https://youtu.be/a',
    );
    expect(
      (json['events'] as List).cast<Map<String, Object?>>().map(
        (e) => e['type'],
      ),
      contains('photoUpload'),
    );
  });
}
