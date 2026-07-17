// 제안 라벨 결정 순서와 부족 4개+ 제외 — 스펙 #13이 순서를 고정한 규칙(#18).
import 'package:cookmark/domain/suggestion.dart';
import 'package:flutter_test/flutter_test.dart';

Suggestion suggestionWith({
  List<MissingIngredient> missing = const [],
  SuggestionSource source = SuggestionSource.generated,
  String menu = '김치찌개',
}) => Suggestion(
  menu: menu,
  source: source,
  missing: missing,
  reason: '근거 한 줄',
  recipeUrl: source == SuggestionSource.saved ? 'https://youtu.be/x' : null,
);

void main() {
  group('제안 라벨 결정 순서 (고정 — 스펙 #13)', () {
    test('부족 0 = 바로 가능', () {
      expect(suggestionWith().label, SuggestionLabel.ready);
    });

    test('부족 1~3이 전부 대체재로 해소 = 애매하지만 가능', () {
      final s = suggestionWith(
        missing: const [
          MissingIngredient(name: '우유', substitute: '두유'),
          MissingIngredient(name: '버터', substitute: '식용유'),
        ],
      );
      expect(s.label, SuggestionLabel.maybe);
    });

    test('그 외 부족 1~3 = 이것만 사면 가능', () {
      expect(
        suggestionWith(missing: const [MissingIngredient(name: '고춧가루')]).label,
        SuggestionLabel.buyOne,
      );
    });

    test('하나라도 대체재가 없으면 "이것만 사면 가능"이다 — 순서가 그렇게 고정돼 있다', () {
      final s = suggestionWith(
        missing: const [
          MissingIngredient(name: '우유', substitute: '두유'),
          MissingIngredient(name: '고춧가루'),
        ],
      );
      expect(s.label, SuggestionLabel.buyOne);
    });

    test('부족이 있으면 절대 "바로 가능"이 아니다', () {
      final s = suggestionWith(
        missing: const [MissingIngredient(name: '우유', substitute: '두유')],
      );
      expect(s.label, isNot(SuggestionLabel.ready));
    });

    test('라벨 문구는 CONTEXT.md 글로서리를 따른다', () {
      expect(SuggestionLabel.ready.text, '바로 가능');
      expect(SuggestionLabel.maybe.text, '애매하지만 가능');
      expect(SuggestionLabel.buyOne.text, '이것만 사면 가능');
    });
  });

  group('부족 4개 이상 제외', () {
    test('부족 3개는 아직 제안이다', () {
      final s = suggestionWith(
        missing: const [
          MissingIngredient(name: 'a'),
          MissingIngredient(name: 'b'),
          MissingIngredient(name: 'c'),
        ],
      );
      expect(s.isActionable, isTrue);
    });

    test('부족 4개는 제안이 아니라 장보기 목록이다', () {
      final s = suggestionWith(
        missing: const [
          MissingIngredient(name: 'a'),
          MissingIngredient(name: 'b'),
          MissingIngredient(name: 'c'),
          MissingIngredient(name: 'd'),
        ],
      );
      expect(s.isActionable, isFalse);
    });

    test('대체재로 다 해소돼도 4개면 제외된다 — 개수가 기준이다', () {
      final s = suggestionWith(
        missing: const [
          MissingIngredient(name: 'a', substitute: 'A'),
          MissingIngredient(name: 'b', substitute: 'B'),
          MissingIngredient(name: 'c', substitute: 'C'),
          MissingIngredient(name: 'd', substitute: 'D'),
        ],
      );
      expect(s.isActionable, isFalse);
    });
  });

  group('selectSuggestions', () {
    test('저장 레시피 매칭이 우선이고 모자라면 AI 제안으로 채운다', () {
      final selection = selectSuggestions([
        suggestionWith(menu: 'AI 1'),
        suggestionWith(menu: '저장 1', source: SuggestionSource.saved),
        suggestionWith(menu: 'AI 2'),
        suggestionWith(menu: '저장 2', source: SuggestionSource.saved),
      ]);

      expect(selection.shown.map((s) => s.menu), ['저장 1', '저장 2', 'AI 1']);
    });

    test('합계 3개를 넘지 않는다 — "오늘 할 3개"', () {
      final selection = selectSuggestions([
        for (var i = 0; i < 6; i++) suggestionWith(menu: '메뉴$i'),
      ]);
      expect(selection.shown, hasLength(maxSuggestions));
    });

    test('저장 레시피가 3개를 넘으면 AI 제안은 안 들어간다', () {
      final selection = selectSuggestions([
        for (var i = 0; i < 4; i++)
          suggestionWith(menu: '저장$i', source: SuggestionSource.saved),
        suggestionWith(menu: 'AI'),
      ]);
      expect(
        selection.shown.every((s) => s.source == SuggestionSource.saved),
        isTrue,
      );
    });

    test('부족 4개 이상은 빠지고 몇 개가 빠졌는지 센다 — 투명성 줄의 숫자', () {
      final fat = suggestionWith(
        menu: '뚱뚱',
        missing: const [
          MissingIngredient(name: 'a'),
          MissingIngredient(name: 'b'),
          MissingIngredient(name: 'c'),
          MissingIngredient(name: 'd'),
        ],
      );
      final selection = selectSuggestions([
        suggestionWith(menu: '괜찮'),
        fat,
        fat,
      ]);

      expect(selection.shown.map((s) => s.menu), ['괜찮']);
      expect(selection.excludedCount, 2);
    });

    test('제외 수는 3개 상한 때문에 잘린 것까지 세지 않는다 — 부족 4개+만 센다', () {
      final selection = selectSuggestions([
        for (var i = 0; i < 5; i++) suggestionWith(menu: '메뉴$i'),
      ]);

      expect(selection.shown, hasLength(3));
      expect(
        selection.excludedCount,
        0,
        reason: '상한으로 잘린 건 "부족 4개 이상이라 제외"가 아니다',
      );
    });

    test('전부 제외되면 빈 목록과 제외 수만 남는다', () {
      final fat = suggestionWith(
        missing: const [
          MissingIngredient(name: 'a'),
          MissingIngredient(name: 'b'),
          MissingIngredient(name: 'c'),
          MissingIngredient(name: 'd'),
        ],
      );
      final selection = selectSuggestions([fat, fat]);

      expect(selection.shown, isEmpty);
      expect(selection.excludedCount, 2);
    });

    test('빈 입력은 빈 결과다', () {
      final selection = selectSuggestions([]);
      expect(selection.shown, isEmpty);
      expect(selection.excludedCount, 0);
    });
  });

  test('SuggestionSource.parse는 스키마 밖 값을 버린다', () {
    expect(SuggestionSource.parse('saved'), SuggestionSource.saved);
    expect(SuggestionSource.parse('generated'), SuggestionSource.generated);
    expect(SuggestionSource.parse('bookmarked'), isNull);
    expect(SuggestionSource.parse(null), isNull);
  });
}
