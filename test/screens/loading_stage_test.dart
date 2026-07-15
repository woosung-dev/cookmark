// 로딩 단계식 문구 유닛 — G1 #8이 정한 0~3초/3~10초/10초 취소/30초 타임아웃 경계
import 'package:cookmark/screens/loading_stage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LoadingStage at(int seconds) =>
      LoadingStage.forElapsed(Duration(seconds: seconds));

  group('단계 경계 — 기다림이 불안하지 않게 (G1 #8)', () {
    test('0~3초는 첫 문구다', () {
      expect(at(0), LoadingStage.scanning);
      expect(at(2), LoadingStage.scanning);
    });

    test('3~10초는 두 번째 문구로 넘어간다', () {
      expect(at(3), LoadingStage.stillWorking);
      expect(at(9), LoadingStage.stillWorking);
    });

    test('10초부터는 취소가 등장하는 단계다', () {
      expect(at(10), LoadingStage.cancellable);
      expect(at(29), LoadingStage.cancellable);
    });

    test('30초에 타임아웃 단계가 된다', () {
      expect(at(30), LoadingStage.timedOut);
      expect(at(45), LoadingStage.timedOut);
    });
  });

  group('취소 노출 — 10초 전에는 없다', () {
    test('10초 전 단계는 취소를 내보이지 않는다', () {
      expect(LoadingStage.scanning.showsCancel, isFalse);
      expect(LoadingStage.stillWorking.showsCancel, isFalse);
    });

    test('10초 이후 단계는 취소를 내보인다', () {
      expect(LoadingStage.cancellable.showsCancel, isTrue);
    });
  });

  group('문구 — 각 단계가 서로 다른 말을 한다', () {
    test('단계마다 비어 있지 않은 고유 문구가 있다', () {
      final messages = [
        LoadingStage.scanning,
        LoadingStage.stillWorking,
        LoadingStage.cancellable,
      ].map((s) => s.message).toList();

      expect(messages.every((m) => m.isNotEmpty), isTrue);
      expect(messages.toSet(), hasLength(3));
    });
  });
}
