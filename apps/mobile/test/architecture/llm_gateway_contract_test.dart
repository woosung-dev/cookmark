// 서버 경계 계약의 트립와이어 — 응답을 파싱하는 구현의 모든 seam 메서드가 정규화 래퍼를
// 통과함을 강제한다(#142, #168로 기기 세션 경계까지 확장).
//
// 왜 이 파일이 있나: 계약("정규화되지 않은 실패가 경계 밖으로 새지 않는다")이 래퍼를
// 손으로 붙이는 관례로만 남으면, 다음 세션이 네 번째 메서드를 래퍼 없이 붙이고 계약이 조용히
// 부패한다. 이건 가정이 아니라 이 리포가 이미 겪은 일이다 — 폐기된 arm #25를 죽인 오형식 200
// 고착이 랜딩된 arm #26에 그대로 살아서 D0 이틀 전까지 왔다. 그래서 관례를 결정론적 테스트로
// 못박는다(선례: navigation_test.dart의 go_router 면제 트립와이어).
//
// 경계가 늘면 여기 [_boundaries]에 한 줄을 더한다 — 계약이 경계마다 따로 발명되지 않게.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 계약을 지는 경계 하나 — 어디를 뒤지고, 무엇이 구현이고, 무엇을 감싸야 하는가.
typedef _Boundary = ({
  String label,
  String directory,
  String marker,
  String wrapper,
  List<String> seamMethods,
  String consequence,
});

const _boundaries = <_Boundary>[
  (
    label: 'LLM 경계',
    directory: 'lib/llm',
    marker: 'implements LlmGateway',
    wrapper: 'normalizeLlmFailures',
    // LlmGateway가 규정하는 seam 메서드 — 셋 다 신뢰할 수 없는 응답을 해석한다.
    seamMethods: ['recognize', 'extractIngredients', 'match'],
    consequence:
        '200인데 모양이 다른 응답의 TypeError가 그 메서드로 새면 컨트롤러가 phase를 '
        '실패로 못 넘겨 화면이 로딩에 영구 고착한다(#142).',
  ),
  (
    label: '기기 세션 경계',
    directory: 'lib/auth',
    marker: 'implements DeviceSession',
    wrapper: 'normalizeDeviceSessionFailures',
    seamMethods: ['token', 'reregister'],
    consequence:
        '등록 응답의 형식 불일치가 정규화되지 않으면 부팅 경로에서 그대로 터진다 — '
        '화면에 로그인도 에러도 없는 경계라 사용자에겐 앱이 그냥 죽은 것으로 보인다(#168).',
  ),
];

/// 선언 직후 이 길이 안에서 래퍼가 보여야 한다 — 저 아래 헬퍼에 있는 이름이
/// 우연히 통과시키지 않도록 검사 범위를 선언부로 묶는다.
const _declarationWindow = 200;

void main() {
  for (final boundary in _boundaries) {
    test('${boundary.label}는 seam 메서드를 전부 ${boundary.wrapper}로 감싼다', () {
      // 대상은 HTTP 응답을 해석하는 구현뿐이다. 페이크는 파싱을 안 하고 정규화된 실패를 직접
      // 던지므로 감쌀 것이 없다 — http.Client 사용 여부로 가른다.
      final implementations = [
        for (final entity in Directory(boundary.directory).listSync())
          if (entity is File && entity.path.endsWith('.dart'))
            if (entity.readAsStringSync() case final source
                when source.contains(boundary.marker) &&
                    source.contains('http.Client'))
              (path: entity.path, source: source),
      ];

      expect(
        implementations,
        isNotEmpty,
        reason: '${boundary.directory}에서 구현을 못 찾았다 — 이 트립와이어가 아무것도 안 지키고 있다',
      );

      final unwrapped = <String>[];
      for (final implementation in implementations) {
        // @override로 잘라 메서드 단위 조각을 만든다. 각 조각의 머리가 선언이다.
        for (final segment
            in implementation.source.split('@override').skip(1)) {
          final head = segment.substring(
            0,
            segment.length < _declarationWindow
                ? segment.length
                : _declarationWindow,
          );
          for (final method in boundary.seamMethods) {
            if (!RegExp('\\b$method\\s*\\(').hasMatch(head)) continue;
            if (!head.contains(boundary.wrapper)) {
              unwrapped.add('${implementation.path}의 $method');
            }
          }
        }
      }

      expect(
        unwrapped,
        isEmpty,
        reason:
            '$unwrapped가 ${boundary.wrapper}를 안 거친다. ${boundary.consequence} '
            '예외 유형을 열거해 잡지 말고 선언을 `=> ${boundary.wrapper}(() async {...})`로 감싸라.',
      );
    });
  }
}
