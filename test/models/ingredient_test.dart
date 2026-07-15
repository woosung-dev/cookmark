// 재료 모델 유닛 — confidence 3단 초기 상태 산식(ADR-0003과 한 몸) 검증
import 'package:cookmark/models/ingredient.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('인식 결과의 confidence 초기 상태 (ADR-0003 — 변경 시 수동 수정 산식 재검토)', () {
    test('high는 체크된 상태로 시작한다', () {
      final it = Ingredient.fromRecognition(name: '대파', confidence: Confidence.high);
      expect(it.checked, isTrue);
    });

    test('medium은 체크된 상태로 시작한다 (물음표 점은 표시 층위)', () {
      final it = Ingredient.fromRecognition(name: '두부', confidence: Confidence.medium);
      expect(it.checked, isTrue);
    });

    test('low는 해제된 상태로 시작한다 — 환각을 매칭에서 배제', () {
      final it = Ingredient.fromRecognition(name: '트러플', confidence: Confidence.low);
      expect(it.checked, isFalse);
    });
  });

  group('Confidence 파싱 — 프록시 JSON의 문자열 계약', () {
    test('high/medium/low 문자열을 파싱한다', () {
      expect(Confidence.parse('high'), Confidence.high);
      expect(Confidence.parse('medium'), Confidence.medium);
      expect(Confidence.parse('low'), Confidence.low);
    });

    test('모르는 값은 low로 떨어진다 — 환각을 체크된 채로 들이지 않는다', () {
      expect(Confidence.parse('보통'), Confidence.low);
      expect(Confidence.parse(''), Confidence.low);
    });
  });

  group('토글 — 해제=매칭 제외 (삭제 개념 없음)', () {
    test('toggled()는 checked만 뒤집고 name·confidence를 보존한다', () {
      final it = Ingredient.fromRecognition(name: '계란', confidence: Confidence.high);
      final off = it.toggled();
      expect(off.checked, isFalse);
      expect(off.name, '계란');
      expect(off.confidence, Confidence.high);
      expect(off.toggled().checked, isTrue);
    });
  });

  group('직접 추가한 재료', () {
    test('사용자가 추가한 재료는 high·체크로 들어온다', () {
      final it = Ingredient.userAdded('멸치');
      expect(it.checked, isTrue);
      expect(it.confidence, Confidence.high);
    });
  });
}
