// 레시피 북 화면 — 행 탭 열람·삭제 실행취소 토스트·서버 삭제 실패 스낵바(파일럿 완성도 T2).
import 'package:cookmark/data/server_recipe_repository.dart';
import 'package:cookmark/data/storage.dart';
import 'package:cookmark/domain/recipe.dart';
import 'package:cookmark/llm/fake_llm_gateway.dart';
import 'package:cookmark/ui/backup_controller.dart';
import 'package:cookmark/ui/recipe_book_controller.dart';
import 'package:cookmark/ui/recipe_book_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

import '../support/fake_server_recipe_repository.dart';

/// launchUrl을 삼키고 무엇이 열렸는지 기록한다 — 실제 새 탭 열기는 테스트에서 불가
/// (core_loop_test의 _FakeUrlLauncher 관용구).
class _RecordingUrlLauncher extends Fake
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {
  final launched = <String>[];

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launched.add(url);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Storage storage;
  late _RecordingUrlLauncher launcher;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    storage = await Storage.open();
    launcher = _RecordingUrlLauncher();
    UrlLauncherPlatform.instance = launcher;
  });

  Future<void> pumpBook(
    WidgetTester tester,
    RecipeBookController controller,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RecipeBookPage(
          controller: controller,
          backupController: BackupController(storage),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  const url = 'https://youtu.be/abc';

  testWidgets('행을 탭하면 저장한 레시피 원문이 열린다', (tester) async {
    final book = RecipeBookController(FakeLlmGateway(), storage);
    await book.add(url: url, title: '김치찌개');
    await pumpBook(tester, book);

    await tester.tap(find.byKey(const Key('recipe-tile-$url')));
    await tester.pumpAndSettle();

    expect(launcher.launched, [url]);
  });

  testWidgets('삭제하면 실행취소 토스트가 뜨고, 실행취소로 복원된다', (tester) async {
    final book = RecipeBookController(FakeLlmGateway(), storage);
    await book.add(url: url, title: '김치찌개');
    await pumpBook(tester, book);

    await tester.tap(find.byKey(const Key('recipe-remove-$url')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recipe-tile-$url')), findsNothing);
    expect(find.byKey(const Key('recipe-remove-toast')), findsOneWidget);

    await tester.tap(find.text('실행취소'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recipe-tile-$url')), findsOneWidget);
    expect(book.recipes.single.title, '김치찌개');
  });

  testWidgets('서버 삭제 실패(비-404)는 스낵바로 표면화되고 타일은 남는다', (tester) async {
    final server = FakeServerRecipeRepository(
      seed: const [
        Recipe(url: url, title: '김치찌개', ingredients: ['김치']),
      ],
    );
    final book = RecipeBookController(
      FakeLlmGateway(),
      storage,
      server: server,
    );
    await book.hydrate();
    server.failure = const RecipeApiFailure(RecipeApiFailureKind.unavailable);
    await pumpBook(tester, book);

    await tester.tap(find.byKey(const Key('recipe-remove-$url')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('recipe-remove-failure-toast')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('recipe-tile-$url')), findsOneWidget);
    expect(
      find.byKey(const Key('recipe-remove-toast')),
      findsNothing,
      reason: '서버 모드엔 실행취소가 없다 — undo는 재-POST 재추출이라 범위 밖',
    );
  });

  testWidgets('서버 삭제 성공엔 실행취소 토스트가 없다 — 그냥 사라진다', (tester) async {
    final server = FakeServerRecipeRepository(
      seed: const [
        Recipe(url: url, title: '김치찌개', ingredients: ['김치']),
      ],
    );
    final book = RecipeBookController(
      FakeLlmGateway(),
      storage,
      server: server,
    );
    await book.hydrate();
    await pumpBook(tester, book);

    await tester.tap(find.byKey(const Key('recipe-remove-$url')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('recipe-tile-$url')), findsNothing);
    expect(find.byKey(const Key('recipe-remove-toast')), findsNothing);
    expect(find.byKey(const Key('recipe-remove-failure-toast')), findsNothing);
  });
}
