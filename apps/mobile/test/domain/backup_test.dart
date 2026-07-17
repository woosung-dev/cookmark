// 백업 병합과 주간 성적표 — 유실 보험이자 파일럿 데이터의 유일한 수집 경로(#20).
import 'package:cookmark/domain/app_event.dart';
import 'package:cookmark/domain/backup.dart';
import 'package:cookmark/domain/recipe.dart';
import 'package:flutter_test/flutter_test.dart';

Recipe recipeAt(String id) =>
    Recipe(url: 'https://youtu.be/$id', title: '요리$id', ingredients: ['재료$id']);

AppEvent uploadAt(DateTime at) =>
    AppEvent.photoUpload(at: at, bytes: 1, width: 768);

BackupData backupOf({
  List<Recipe> recipes = const [],
  List<AppEvent> events = const [],
}) => BackupData(
  recipes: recipes,
  events: events,
  exportedAt: DateTime.utc(2026, 7, 15),
);

void main() {
  group('JSON 왕복', () {
    test('레시피 북과 이벤트 로그가 한 파일에 담긴다 (US 30)', () {
      final original = backupOf(
        recipes: [recipeAt('a')],
        events: [uploadAt(DateTime.utc(2026, 7, 15, 19))],
      );
      final restored = BackupData.fromJson(original.toJson());

      expect(restored.recipes.single.url, 'https://youtu.be/a');
      expect(restored.events.single.type, AppEventType.photoUpload);
      expect(restored.exportedAt, original.exportedAt);
    });

    test('버전이 붙는다 — 나중에 형식이 바뀌어도 옛 백업을 읽을 수 있게', () {
      expect(backupOf().toJson()['version'], 1);
    });

    test('앞선 버전이 만든 백업도 가져올 수 있다 — 모르는 이벤트가 있어도', () {
      final restored = BackupData.fromJson(const {
        'version': 1,
        'exportedAt': '2026-07-15T00:00:00.000Z',
        'recipes': <Object?>[],
        'events': [
          {'type': 'photoUpload', 'at': '2026-07-15T19:00:00.000Z'},
          {'type': '앞선버전이벤트', 'at': '2026-07-15T19:01:00.000Z'},
        ],
      });

      expect(restored.events.map((e) => e.type), [AppEventType.photoUpload]);
    });
  });

  group('레시피 병합 — URL 중복 제거', () {
    test('겹치지 않는 레시피는 들어온다', () {
      final merge = previewMerge(
        current: backupOf(recipes: [recipeAt('a')]),
        incoming: backupOf(recipes: [recipeAt('b')]),
      );

      expect(merge.newRecipes.map((r) => r.url), ['https://youtu.be/b']);
      expect(merge.mergedRecipes, hasLength(2));
    });

    test('같은 URL은 건너뛴다 — 배우자 기기 시딩이 두 배로 늘지 않는다', () {
      final merge = previewMerge(
        current: backupOf(recipes: [recipeAt('a')]),
        incoming: backupOf(recipes: [recipeAt('a')]),
      );

      expect(merge.newRecipes, isEmpty);
      expect(merge.duplicateRecipeCount, 1);
      expect(merge.mergedRecipes, hasLength(1));
    });

    test('겹치면 지금 것을 남긴다 — 내 기기의 기록이 더 정확하다', () {
      const mine = Recipe(
        url: 'https://youtu.be/a',
        title: '내 제목',
        ingredients: ['내 재료'],
      );
      const theirs = Recipe(
        url: 'https://youtu.be/a',
        title: '남의 제목',
        ingredients: ['남의 재료'],
      );
      final merge = previewMerge(
        current: backupOf(recipes: [mine]),
        incoming: backupOf(recipes: [theirs]),
      );

      expect(merge.mergedRecipes.single.title, '내 제목');
    });

    test('들어온 것끼리 겹쳐도 한 번만 들어온다', () {
      final merge = previewMerge(
        current: backupOf(),
        incoming: backupOf(recipes: [recipeAt('a'), recipeAt('a')]),
      );

      expect(merge.newRecipes, hasLength(1));
      expect(merge.duplicateRecipeCount, 1);
    });
  });

  group('이벤트 로그는 가져오지 않는다 (US 25·US 30)', () {
    test('들어온 백업의 이벤트는 무시된다', () {
      final merge = previewMerge(
        current: backupOf(events: [uploadAt(DateTime.utc(2026, 7, 15, 19))]),
        incoming: backupOf(events: [uploadAt(DateTime.utc(2026, 7, 15, 20))]),
      );

      expect(merge.ignoredEventCount, 1);
    });

    test('배우자 기기 시딩이 내 로그를 남의 이벤트로 오염시키지 않는다', () {
      // 이게 깨지면 다음 주 export가 남의 이벤트를 되뱉어 US 30의 인별 귀속이 무너진다.
      final merge = previewMerge(
        current: backupOf(recipes: [recipeAt('mine')]),
        incoming: backupOf(
          recipes: [recipeAt('theirs')],
          events: [
            uploadAt(DateTime.utc(2026, 7, 15, 19)),
            uploadAt(DateTime.utc(2026, 7, 15, 20)),
          ],
        ),
      );

      expect(merge.newRecipes.map((r) => r.url), ['https://youtu.be/theirs']);
      expect(merge.ignoredEventCount, 2);
    });

    test('레시피가 없으면 바뀌는 게 없다 — 이벤트만 잔뜩 들어와도', () {
      final merge = previewMerge(
        current: backupOf(recipes: [recipeAt('a')]),
        incoming: backupOf(
          recipes: [recipeAt('a')],
          events: [uploadAt(DateTime.utc(2026, 7, 15, 19))],
        ),
      );

      expect(merge.changesNothing, isTrue);
    });
  });

  group('미리보기', () {
    test('바뀌는 게 없으면 알려준다', () {
      final merge = previewMerge(current: backupOf(), incoming: backupOf());
      expect(merge.changesNothing, isTrue);
    });

    test('병합 요약이 이벤트에 실릴 모양을 만든다', () {
      final at = DateTime.utc(2026, 7, 15, 19);
      final merge = previewMerge(
        current: backupOf(recipes: [recipeAt('a')], events: [uploadAt(at)]),
        incoming: backupOf(
          recipes: [recipeAt('a'), recipeAt('b')],
          events: [uploadAt(at), uploadAt(DateTime.utc(2026, 7, 15, 20))],
        ),
      );

      expect(merge.toSummary(), {
        'newRecipes': 1,
        'duplicateRecipes': 1,
        'ignoredEvents': 2,
      });
    });
  });

  group('주간 성적표 (ADR-0004 단일맹검)', () {
    final now = DateTime.utc(2026, 7, 15, 20);

    test('이번 주 업로드와 이거 했어요만 센다', () {
      final report = weeklyReportFrom([
        uploadAt(now.subtract(const Duration(days: 1))),
        uploadAt(now.subtract(const Duration(days: 2))),
        AppEvent.checklistEdit(
          at: now,
          kind: EditKind.uncheck,
          path: EditPath.row,
          name: '대파',
        ),
      ], now);

      expect(report.uploads, 2);
      expect(report.cooked, 0);
    });

    test('7일보다 오래된 건 안 센다', () {
      final report = weeklyReportFrom([
        uploadAt(now.subtract(const Duration(days: 8))),
        uploadAt(now.subtract(const Duration(days: 1))),
      ], now);

      expect(report.uploads, 1);
    });

    test('카피는 G1 #8이 정한 문장이다', () {
      expect(
        const WeeklyReport(uploads: 4, cooked: 2).copy,
        '이번 주 업로드 4회, 이거 했어요 2회 — 기록 저장하기',
      );
    });

    test('수동 수정 수는 성적표에 존재하지 않는다 — 배우자에게 계측을 알리지 않는다', () {
      final report = weeklyReportFrom([
        for (var i = 0; i < 20; i++)
          AppEvent.checklistEdit(
            at: now,
            kind: EditKind.uncheck,
            path: EditPath.row,
            name: '재료$i',
          ),
      ], now);

      // 수정을 20번 했어도 성적표에 드러나는 숫자는 0이다.
      expect(report.uploads, 0);
      expect(report.cooked, 0);
      expect(report.copy, isNot(contains('20')));
      expect(report.copy, isNot(contains('수정')));
    });
  });
}
