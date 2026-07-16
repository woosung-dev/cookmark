// go_router 면제(#50)를 지키는 트립와이어 — 명령형 화면 push가 정확히 1건임을 강제한다.
//
// 왜 이 파일이 있나: ADR-0001이 화면을 2개로 고정했고 in-app 네비게이션 그래프가 1개 엣지
// (MainPage → RecipeBookPage)뿐이라, mobile.md §5의 go_router를 면제하고 단일 Navigator.push를
// 유지하기로 했다(#50). 프로즈 예외만으로는 다음 세션이 3번째 화면에 push를 또 붙이고 예외가
// 조용히 부패한다 — 이 리포가 겪은 실패다. 그래서 예외를 자족 결정론적 테스트로 못박는다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('명령형 화면 push는 정확히 1건 — 축복받은 _openRecipeBook만 (go_router 면제 #50)', () {
    // Navigator.of(context).push / Navigator.push 계열(pushNamed·pushReplacement 등)을 센다.
    // pop은 세지 않는다 — 복귀는 허용된다(#50).
    final pushPattern = RegExp(
      r'Navigator\s*\.\s*(of\s*\([^)]*\)\s*\.\s*)?push\w*\s*\(',
    );

    final callSites = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        // 주석은 제외한다 — 축복받은 push의 헤더 주석이 "push"라는 단어를 담을 수 있다.
        final code = lines[i].split('//').first;
        if (pushPattern.hasMatch(code)) {
          callSites.add('${entity.path}:${i + 1}');
        }
      }
    }

    expect(
      callSites,
      hasLength(1),
      reason:
          '명령형 화면 push가 ${callSites.length}건이다 ($callSites). '
          '2번째 화면 이동을 추가하려면 먼저 go_router 도입을 재결정하라 '
          '(#50 예외, docs/coding-standards.md 참조).',
    );
    expect(
      callSites.single,
      contains('main_page.dart'),
      reason:
          '축복받은 단일 push는 main_page.dart의 _openRecipeBook이어야 한다. '
          '다른 곳으로 옮겼다면 go_router 재결정을 먼저 하라 (#50).',
    );
  });
}
