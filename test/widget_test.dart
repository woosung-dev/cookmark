// 냉파 홈 화면 스모크 테스트 — 앱이 뜨고 핵심 CTA/카피가 보이는지
import 'package:flutter_test/flutter_test.dart';

import 'package:cookmark/main.dart';

void main() {
  testWidgets('온보딩 홈: 냉파 타이틀·사진 올리기 CTA·탭바 렌더', (tester) async {
    await tester.pumpWidget(const CookmarkApp());

    expect(find.text('냉파'), findsOneWidget);
    expect(find.text('냉장고 사진 올리기'), findsOneWidget);
    expect(find.text('출처 있는, 내가 저장한 레시피만 추천해요.'), findsOneWidget);
    // 하단 탭
    expect(find.text('메인'), findsOneWidget);
    expect(find.text('레시피 북'), findsOneWidget);
  });
}
