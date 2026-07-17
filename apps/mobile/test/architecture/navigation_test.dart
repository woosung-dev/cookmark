// go_router 면제(#50)를 지키는 트립와이어 — 명령형 화면 push가 최대 1건임을 강제한다.
//
// 왜 이 파일이 있나: ADR-0007로 메인↔레시피북은 하단 탭 바(선언형 전환)가 처리하고,
// 제안 상세만 축복받은 단일 명령형 push다. 프로즈 예외만으로는 다음 세션이 또 다른 화면에
// push를 붙이고 예외가 조용히 부패한다 — 이 리포가 겪은 실패다. 그래서 예외를 자족 결정론적
// 테스트로 못박는다. (탭 전환은 setState라 여기 안 걸린다.)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('명령형 화면 push는 최대 1건 — 축복받은 제안 상세만 (go_router 면제 #50)', () {
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
      callSites.length,
      lessThanOrEqualTo(1),
      reason:
          '명령형 화면 push가 ${callSites.length}건이다 ($callSites). '
          '메인↔레시피북은 탭 바(선언형)로 처리하고 제안 상세만 축복받은 단일 push다. '
          '2번째 명령형 push를 추가하려면 먼저 go_router 도입을 재결정하라 '
          '(#50 예외, docs/coding-standards.md 참조).',
    );
    if (callSites.isNotEmpty) {
      expect(
        callSites.single,
        contains('main_page.dart'),
        reason:
            '축복받은 단일 push는 main_page.dart여야 한다. '
            '다른 곳으로 옮겼다면 go_router 재결정을 먼저 하라 (#50).',
      );
    }
  });
}
