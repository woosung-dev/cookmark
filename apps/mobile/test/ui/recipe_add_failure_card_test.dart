// 레시피 저장 실패 카드 — 죽은 서버가 신고 없이 지나가지 않는다(#127 항목 ③, 스펙 #161 §G).
import 'package:cookmark/data/server_recipe_repository.dart';
import 'package:cookmark/ui/widgets/recipe_add_failure_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpCard(WidgetTester tester, RecipeApiFailureKind kind) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecipeAddFailureCard(
            kind: kind,
            onRetry: () {},
            onDismiss: () {},
          ),
        ),
      ),
    );
  }

  // 하드코딩이 의도다 — 위젯의 분류 로직을 불러 쓰면 분류가 드리프트할 때 테스트가 따라 움직인다.
  // RecipeApiFailureKind에는 LlmFailureKind의 empty·lowQuality 같은 "사용자 입력이 원인인" 값이
  // 하나도 없다. 502조차 서버 LLM 자체 다운일 때만 나므로 4종 전부가 신고 대상이다.
  for (final kind in RecipeApiFailureKind.values) {
    testWidgets('$kind — 신고 유도 줄이 뜬다', (tester) async {
      await pumpCard(tester, kind);

      expect(find.byKey(const Key('recipe-add-report-hint')), findsOneWidget);
      expect(find.textContaining('카톡으로 알려주세요'), findsOneWidget);
    });
  }

  testWidgets('재시도·닫기 두 길은 그대로다 — 막다른 카드가 되지 않는다 (G1 #8)', (tester) async {
    await pumpCard(tester, RecipeApiFailureKind.unavailable);

    expect(find.byKey(const Key('recipe-add-retry')), findsOneWidget);
    expect(find.byKey(const Key('recipe-add-dismiss')), findsOneWidget);
  });
}
