// confidence 3단 초기 상태 — ADR-0003의 수동 수정 산식과 한 몸이라 회귀하면 킬 기준이 흔들린다.
import 'package:cookmark/domain/ingredient.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('confidence 초기 체크 상태 (ADR-0003)', () {
    test('high는 체크된 채로 시작한다', () {
      expect(
        Ingredient.recognized(name: '대파', confidence: Confidence.high).checked,
        isTrue,
      );
    });

    test('medium도 체크된 채로 시작한다 — 물음표 점만 붙는다', () {
      expect(
        Ingredient.recognized(
          name: '애호박',
          confidence: Confidence.medium,
        ).checked,
        isTrue,
      );
    });

    test('low는 해제된 채로 시작한다 — 환각을 그냥 두면 매칭에서 빠진다', () {
      expect(
        Ingredient.recognized(name: '표고버섯', confidence: Confidence.low).checked,
        isFalse,
      );
    });
  });

  test('직접 추가한 재료는 confidence가 없고 항상 체크다', () {
    const added = Ingredient.added('두유');
    expect(added.confidence, isNull);
    expect(added.checked, isTrue);
  });

  group('Confidence.parse', () {
    test('3단을 그대로 읽는다', () {
      expect(Confidence.parse('high'), Confidence.high);
      expect(Confidence.parse('medium'), Confidence.medium);
      expect(Confidence.parse('low'), Confidence.low);
    });

    test('모델이 스키마를 벗어난 값을 뱉으면 null이다', () {
      expect(Confidence.parse('very-high'), isNull);
      expect(Confidence.parse(null), isNull);
      expect(Confidence.parse(''), isNull);
    });
  });

  test('JSON 왕복에서 이름·confidence·체크 상태가 보존된다', () {
    final original = Ingredient.recognized(
      name: '계란',
      confidence: Confidence.medium,
    ).copyWith(checked: false);
    expect(Ingredient.fromJson(original.toJson()), original);
  });

  test('직접 추가 항목의 JSON 왕복 — confidence 없음이 유지된다', () {
    const original = Ingredient.added('두유');
    final restored = Ingredient.fromJson(original.toJson());
    expect(restored.confidence, isNull);
    expect(restored.name, '두유');
    expect(restored.checked, isTrue);
  });
}
