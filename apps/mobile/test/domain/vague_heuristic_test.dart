// 뭉뚱그림 휴리스틱 — ADR-0002. 오탐은 구조적으로 가능하고, 그건 탭 1회로 되돌린다.
import 'package:cookmark/domain/ingredient.dart';
import 'package:cookmark/domain/vague_heuristic.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('접미 신호 (~통/~류)', () {
    test('"반찬통"은 뭉뚱그림이다 — P1 실측에서 flash-lite가 실제로 낸 출력', () {
      expect(isVagueItem(name: '반찬통', confidence: Confidence.medium), isTrue);
    });

    test('"소스류"는 뭉뚱그림이다', () {
      expect(isVagueItem(name: '소스류', confidence: Confidence.medium), isTrue);
    });

    test('접미 신호는 confidence와 무관하게 잡는다 — 그 자체로 정보량이 0이다', () {
      for (final c in Confidence.values) {
        expect(
          isVagueItem(name: '김치통', confidence: c),
          isTrue,
          reason: '$c',
        );
      }
    });

    test('"육류"처럼 범주를 가리키는 것도 잡는다', () {
      expect(isVagueItem(name: '육류', confidence: Confidence.high), isTrue);
    });
  });

  group('범주어 + low confidence 가중', () {
    test('"통조림"은 low일 때 뭉뚱그림이다', () {
      expect(isVagueItem(name: '통조림', confidence: Confidence.low), isTrue);
    });

    test('같은 "통조림"도 high면 그냥 둔다 — 모델이 확신하면 믿는다', () {
      expect(isVagueItem(name: '통조림', confidence: Confidence.high), isFalse);
    });

    test('"반찬"은 low일 때 뭉뚱그림이다', () {
      expect(isVagueItem(name: '반찬', confidence: Confidence.low), isTrue);
    });
  });

  group('구체 재료는 건드리지 않는다', () {
    for (final name in ['대파', '계란', '두부', '애호박', '고추장', '표고버섯', '간장', '된장']) {
      test('"$name"은 뭉뚱그림이 아니다', () {
        for (final c in Confidence.values) {
          expect(
            isVagueItem(name: name, confidence: c),
            isFalse,
            reason: '$c',
          );
        }
      });
    }
  });

  test('사용자가 직접 적은 재료는 뭉뚱그림으로 보지 않는다 — 본인이 아는 것을 적은 것이다', () {
    expect(isVagueItem(name: '반찬통', confidence: null), isFalse);
  });

  group('parseSubstitution', () {
    test('쉼표로 가른다', () {
      expect(parseSubstitution('멸치볶음, 김'), ['멸치볶음', '김']);
    });

    test('공백을 다듬는다', () {
      expect(parseSubstitution('  멸치볶음 ,  김  '), ['멸치볶음', '김']);
    });

    test('빈 조각은 버린다', () {
      expect(parseSubstitution('멸치볶음, , 김,'), ['멸치볶음', '김']);
    });

    test('하나만 적어도 된다', () {
      expect(parseSubstitution('멸치볶음'), ['멸치볶음']);
    });

    test('빈 입력은 빈 목록이다', () {
      expect(parseSubstitution('   '), isEmpty);
    });
  });

  group('Ingredient가 태어날 때 분류된다', () {
    test('인식된 "반찬통"은 isVague가 참이다', () {
      expect(
        Ingredient.recognized(
          name: '반찬통',
          confidence: Confidence.medium,
        ).isVague,
        isTrue,
      );
    });

    test('직접 추가한 재료는 isVague가 거짓이다', () {
      expect(const Ingredient.added('반찬통').isVague, isFalse);
    });

    test('미치환 뭉뚱그림은 매칭에 가지 않는다 (ADR-0002)', () {
      final vague = Ingredient.recognized(
        name: '반찬통',
        confidence: Confidence.medium,
      );
      expect(vague.checked, isTrue, reason: 'medium이라 체크는 되어 있다');
      expect(vague.goesToMatching, isFalse, reason: '그래도 매칭에는 안 간다');
    });

    test('해제된 재료도 매칭에 가지 않는다', () {
      final unchecked = Ingredient.recognized(
        name: '대파',
        confidence: Confidence.high,
      ).copyWith(checked: false);
      expect(unchecked.goesToMatching, isFalse);
    });

    test('체크된 구체 재료만 매칭에 간다', () {
      expect(
        Ingredient.recognized(
          name: '대파',
          confidence: Confidence.high,
        ).goesToMatching,
        isTrue,
      );
    });

    test('isVague는 JSON 왕복에서 보존된다 — 세션 복원 후에도 칩이 칩이다', () {
      final vague = Ingredient.recognized(
        name: '반찬통',
        confidence: Confidence.medium,
      );
      expect(Ingredient.fromJson(vague.toJson()).isVague, isTrue);
    });
  });
}
