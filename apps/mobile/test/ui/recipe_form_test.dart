// 레시피 저장 폼 — 거절을 그 자리에서 말한다(#127). 두 화면(온보딩·레시피 북)이 이 폼을 공유한다.
import 'package:cookmark/ui/recipe_book_controller.dart';
import 'package:cookmark/ui/widgets/recipe_form.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const urlField = Key('recipe-url-field');
  const titleField = Key('recipe-title-field');
  const submit = Key('recipe-submit');
  const rejection = Key('recipe-add-rejection');

  /// 넘어온 입력을 기록하고 정해둔 결과를 돌려준다.
  Future<void> pumpForm(
    WidgetTester tester, {
    required RecipeAddOutcome outcome,
    List<(String, String)>? submissions,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecipeForm(
            saving: false,
            onSubmit: (url, title) async {
              submissions?.add((url, title));
              return outcome;
            },
          ),
        ),
      ),
    );
  }

  Future<void> fillAndSubmit(
    WidgetTester tester, {
    String url = 'https://youtu.be/abc',
    String title = '김치찌개',
  }) async {
    await tester.enterText(find.byKey(urlField), url);
    await tester.enterText(find.byKey(titleField), title);
    await tester.tap(find.byKey(submit));
    await tester.pumpAndSettle();
  }

  String textOf(WidgetTester tester, Key key) =>
      tester.widget<TextField>(find.byKey(key)).controller!.text;

  testWidgets('담기면 문구 없이 필드가 비워진다', (tester) async {
    await pumpForm(tester, outcome: RecipeAddOutcome.accepted);
    await fillAndSubmit(tester);

    expect(find.byKey(rejection), findsNothing);
    expect(textOf(tester, urlField), isEmpty);
    expect(textOf(tester, titleField), isEmpty);
  });

  testWidgets('중복이면 이유를 말하고 입력을 지우지 않는다', (tester) async {
    await pumpForm(tester, outcome: RecipeAddOutcome.duplicateUrl);
    await fillAndSubmit(tester);

    expect(find.byKey(rejection), findsOneWidget);
    expect(find.text('이미 레시피 북에 있는 링크예요.'), findsOneWidget);
    // 지워버리면 "담겼나?"와 구분되지 않는다 — 조용한 무시의 원래 증상이 그것이었다.
    expect(textOf(tester, urlField), 'https://youtu.be/abc');
    expect(textOf(tester, titleField), '김치찌개');
  });

  testWidgets('빈 입력도 이유를 말한다 — 조용한 무시가 아니다', (tester) async {
    final submissions = <(String, String)>[];
    await pumpForm(
      tester,
      outcome: RecipeAddOutcome.incomplete,
      submissions: submissions,
    );
    await fillAndSubmit(tester, title: '   ');

    expect(find.byKey(rejection), findsOneWidget);
    expect(find.text('링크와 제목을 모두 채워주세요.'), findsOneWidget);
    // 빈 값 판정도 컨트롤러가 한다 — 폼이 먼저 잘라내면 판정이 두 곳으로 갈린다.
    expect(submissions, [('https://youtu.be/abc', '')]);
  });

  testWidgets('필드를 고치면 거절 문구가 걷힌다 — 고친 URL 밑에 남으면 그 문구가 거짓말이다', (tester) async {
    await pumpForm(tester, outcome: RecipeAddOutcome.duplicateUrl);
    await fillAndSubmit(tester);
    expect(find.byKey(rejection), findsOneWidget);

    await tester.enterText(find.byKey(urlField), 'https://youtu.be/xyz');
    await tester.pump();

    expect(find.byKey(rejection), findsNothing);
  });

  testWidgets('저장 중이면(busy) 문구를 띄우지 않는다 — 진행 표시가 이미 피드백이다', (tester) async {
    await pumpForm(tester, outcome: RecipeAddOutcome.busy);
    await fillAndSubmit(tester);

    expect(find.byKey(rejection), findsNothing);
  });

  testWidgets('거절 뒤 고쳐서 담으면 문구가 걷힌다', (tester) async {
    // 결과를 도중에 바꿀 수 있게 직접 조립한다.
    var outcome = RecipeAddOutcome.duplicateUrl;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecipeForm(
            saving: false,
            onSubmit: (url, title) async => outcome,
          ),
        ),
      ),
    );

    await fillAndSubmit(tester);
    expect(find.byKey(rejection), findsOneWidget);

    outcome = RecipeAddOutcome.accepted;
    await fillAndSubmit(tester, url: 'https://youtu.be/xyz');
    expect(find.byKey(rejection), findsNothing);
  });
}
