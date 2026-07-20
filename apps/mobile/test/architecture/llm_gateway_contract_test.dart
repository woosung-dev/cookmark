// LLM 경계 계약의 트립와이어 — 응답을 파싱하는 게이트웨이 구현의 모든 seam 메서드가
// normalizeLlmFailures를 통과함을 강제한다(#142).
//
// 왜 이 파일이 있나: 계약("정규화되지 않은 실패가 게이트웨이 밖으로 새지 않는다")이 래퍼를
// 손으로 붙이는 관례로만 남으면, 다음 세션이 네 번째 메서드를 래퍼 없이 붙이고 계약이 조용히
// 부패한다. 이건 가정이 아니라 이 리포가 이미 겪은 일이다 — 폐기된 arm #25를 죽인 오형식 200
// 고착이 랜딩된 arm #26에 그대로 살아서 D0 이틀 전까지 왔다. 그래서 관례를 결정론적 테스트로
// 못박는다(선례: navigation_test.dart의 go_router 면제 트립와이어).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// LlmGateway가 규정하는 seam 메서드 — 셋 다 신뢰할 수 없는 응답을 해석한다.
const _seamMethods = ['recognize', 'extractIngredients', 'match'];

/// 선언 직후 이 길이 안에서 래퍼가 보여야 한다 — 저 아래 헬퍼에 있는 이름이
/// 우연히 통과시키지 않도록 검사 범위를 선언부로 묶는다.
const _declarationWindow = 200;

void main() {
  test('응답을 파싱하는 게이트웨이는 seam 메서드를 전부 normalizeLlmFailures로 감싼다 (#142)', () {
    // 대상은 HTTP 응답을 해석하는 구현뿐이다. FakeLlmGateway는 파싱을 안 하고
    // LlmFailure를 직접 던지므로 감쌀 것이 없다 — http.Client 사용 여부로 가른다.
    final implementations = [
      for (final entity in Directory('lib/llm').listSync())
        if (entity is File && entity.path.endsWith('.dart'))
          if (entity.readAsStringSync() case final source
              when source.contains('implements LlmGateway') &&
                  source.contains('http.Client'))
            (path: entity.path, source: source),
    ];

    expect(
      implementations,
      isNotEmpty,
      reason: 'lib/llm에서 게이트웨이 구현을 못 찾았다 — 이 트립와이어가 아무것도 안 지키고 있다',
    );

    final unwrapped = <String>[];
    for (final implementation in implementations) {
      // @override로 잘라 메서드 단위 조각을 만든다. 각 조각의 머리가 선언이다.
      for (final segment in implementation.source.split('@override').skip(1)) {
        final head = segment.substring(
          0,
          segment.length < _declarationWindow
              ? segment.length
              : _declarationWindow,
        );
        for (final method in _seamMethods) {
          if (!RegExp('\\b$method\\s*\\(').hasMatch(head)) continue;
          if (!head.contains('normalizeLlmFailures')) {
            unwrapped.add('${implementation.path}의 $method');
          }
        }
      }
    }

    expect(
      unwrapped,
      isEmpty,
      reason:
          '$unwrapped가 normalizeLlmFailures를 안 거친다. '
          '200인데 모양이 다른 응답의 TypeError가 그 메서드로 새면 컨트롤러가 phase를 '
          '실패로 못 넘겨 화면이 로딩에 영구 고착한다(#142). '
          '예외 유형을 열거해 잡지 말고 선언을 `=> normalizeLlmFailures(() async {...})`로 감싸라.',
    );
  });
}
