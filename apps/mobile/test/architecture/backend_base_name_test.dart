// 백엔드 주소 이름이 갈려 있음을 강제하는 트립와이어 — 한 이름이 두 백엔드를 가리키지 못하게 한다(#164).
//
// 왜 이 파일이 있나: 예전엔 COOKMARK_API_BASE 하나가 프록시 주소로도 apps/api 주소로도 읽혔다.
// 값을 잘못 짚어도 빌드는 둘 다 성공하고 실패만 조용해서(프록시 경로 404 · 계약 불일치),
// 파운더가 핫픽스로 APK를 재빌드할 때마다 지뢰였다(#133 posture). 프로즈 규칙만으로는 다음
// 세션이 "이미 있는 이름"을 재사용하고 규칙이 조용히 부패한다 — 이 리포가 겪은 실패다
// (같은 이유로 go_router 면제가 navigation_test.dart로 못박혀 있다).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `String.fromEnvironment('<name>')` **읽기 지점**만 찾는다. 문자열 등장이 아니라 읽기 지점을
/// 세는 이유 — 헤더 주석이 두 이름을 나란히 설명하고 있어 단순 grep이면 자기 문서에 걸린다.
///
/// 줄 단위가 아니라 **파일 전체**에 건다 — `dart format`이 긴 줄을 감싸면
/// `String.fromEnvironment(\n  'COOKMARK_API_BASE',\n)`가 되고, 줄 단위 스캔은 그걸 못 본다
/// (트립와이어가 조용히 통과하는 위양성 아닌 **위음성**이다).
RegExp _readPattern(String name) =>
    RegExp('String\\s*\\.\\s*fromEnvironment\\s*\\(\\s*[\'"]$name[\'"]');

/// 주석 줄만 걷어낸 소스. `//`를 만난 자리에서 자르지 않는 이유 — 코드 줄에 URL 리터럴
/// (`'http://…'`)이 있으면 그 뒤의 진짜 읽기 지점이 통째로 안 보인다.
String _codeOf(File file) => file
    .readAsLinesSync()
    .where((line) => !line.trimLeft().startsWith('//'))
    .join('\n');

Set<String> _filesReading(String name) {
  final pattern = _readPattern(name);
  final files = <String>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (pattern.hasMatch(_codeOf(entity))) files.add(entity.path);
  }
  return files;
}

void main() {
  test('프록시 주소는 COOKMARK_API_BASE로만 읽힌다 (#164)', () {
    expect(
      _filesReading('COOKMARK_API_BASE'),
      {'lib/llm/proxy_llm_gateway.dart'},
      reason:
          'COOKMARK_API_BASE는 Vercel 서버리스 프록시 전용 이름이다. apps/api(FastAPI) 주소를 '
          '이 이름으로 주입하면 프록시 경로가 404를 내고 빌드는 성공해 실패만 조용해진다. '
          'apps/api 주소는 COOKMARK_SERVER_BASE를 쓴다 (#164, 스펙 #161 §D).',
    );
  });

  test('apps/api 주소는 COOKMARK_SERVER_BASE로만 읽힌다 (#164)', () {
    expect(
      _filesReading('COOKMARK_SERVER_BASE'),
      {'lib/main_api_cutover.dart', 'lib/main_api_spike.dart'},
      reason:
          'COOKMARK_SERVER_BASE는 apps/api를 싣는 엔트리 전용이다. 이 목록이 바뀌었다면 '
          '엔트리가 늘었거나(합류 시 통합 — 스펙 #161 §I) 프록시 경계가 이 이름을 집어삼킨 것이다. '
          '두 이름을 다시 합치려면 프록시 삭제와 같은 PR이어야 한다(폴백이 그 순간 유해로 바뀐다).',
    );
  });
}
