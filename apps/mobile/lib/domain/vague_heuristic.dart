// 뭉뚱그림 항목을 가려내는 클라이언트 휴리스틱 — ADR-0002. 서버에 판정을 맡기지 않는다.
import 'ingredient.dart';

/// 용기·범주를 가리키는 접미. ADR-0002가 지정한 신호다.
const _containerSuffixes = ['통', '류'];

/// 접미가 없어도 범주 수준인 낱말.
///
/// 지어낸 목록이 아니라 P1 #7 실측에서 flash-lite가 실제로 낸 출력이다 —
/// "반찬통", "소스류", "통조림/반찬". 앞의 둘은 접미로 잡히고, 뒤의 둘이 여기 있다.
const _vagueWords = ['반찬', '소스', '통조림'];

/// "반찬통"·"소스류"처럼 용기·범주 수준으로 인식된 항목인가(CONTEXT.md 글로서리).
///
/// 접미(~통/~류)는 그 자체로 신호이고, 그 밖의 범주어는 low confidence일 때만 잡는다
/// ("low confidence 가중", ADR-0002). 오탐은 구조적으로 가능하며, 탭 1회로 되돌릴 수 있어야 한다.
bool isVagueItem({required String name, required Confidence? confidence}) {
  // 사용자가 직접 적어 넣은 재료는 뭉뚱그림이 아니다 — 본인이 아는 것을 적은 것이다.
  if (confidence == null) return false;

  final trimmed = name.trim();
  if (_containerSuffixes.any(trimmed.endsWith)) return true;
  if (confidence == Confidence.low && _vagueWords.any(trimmed.contains)) {
    return true;
  }
  return false;
}

/// 인라인 치환 입력("멸치볶음, 김")을 구체 재료로 가른다.
///
/// 쉼표가 유일한 구분자다 — 사용자가 화면에서 보는 힌트도 쉼표다.
List<String> parseSubstitution(String raw) => [
  for (final part in raw.split(','))
    if (part.trim().isNotEmpty) part.trim(),
];
