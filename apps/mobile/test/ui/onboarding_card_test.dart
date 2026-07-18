// 온보딩 카드의 enabled 배선(#121 수리 R1) — 서버 미러가 ready가 아닌 동안 폼이 실제로 닫히는지.
import 'package:cookmark/ui/widgets/onboarding_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpCard(WidgetTester tester, {required bool enabled}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: OnboardingCard(
              savedCount: 0,
              saving: false,
              enabled: enabled,
              onSubmit: (_, _) {},
              onSkip: () {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('enabled=false면 입력 필드와 담기 버튼이 전부 비활성이다', (tester) async {
    await pumpCard(tester, enabled: false);

    final url = tester.widget<TextField>(
      find.byKey(const Key('recipe-url-field')),
    );
    final title = tester.widget<TextField>(
      find.byKey(const Key('recipe-title-field')),
    );
    final submit = tester.widget<FilledButton>(
      find.byKey(const Key('recipe-submit')),
    );
    expect(url.enabled, isFalse);
    expect(title.enabled, isFalse);
    expect(submit.onPressed, isNull);
  });

  testWidgets('enabled 기본값은 true — 로컬 모드(기존 호출부)는 그대로 활성이다', (tester) async {
    await pumpCard(tester, enabled: true);

    final url = tester.widget<TextField>(
      find.byKey(const Key('recipe-url-field')),
    );
    final submit = tester.widget<FilledButton>(
      find.byKey(const Key('recipe-submit')),
    );
    expect(url.enabled, isTrue);
    expect(submit.onPressed, isNotNull);
  });
}
