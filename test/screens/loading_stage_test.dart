// 로딩 단계식 문구 유닛 — G1 #8이 정한 0~3초/3~10초/10초 취소 경계
import 'package:cookmark/screens/loading_stage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LoadingStage at(int seconds) =>
      LoadingStage.forElapsed(Duration(seconds: seconds));

  group('단계 경계 — 기다림이 불안하지 않게 (G1 #8)', () {
    test('0~3초는 첫 문구다', () {
      expect(at(0), LoadingStage.justStarted);
      expect(at(2), LoadingStage.justStarted);
    });

    test('3~10초는 두 번째 문구로 넘어간다', () {
      expect(at(3), LoadingStage.stillWorking);
      expect(at(9), LoadingStage.stillWorking);
    });

    test('10초부터는 취소가 등장하는 단계다', () {
      expect(at(10), LoadingStage.cancellable);
      expect(at(29), LoadingStage.cancellable);
    });

    test('30초를 넘겨도 문구는 마지막 단계에 머문다 — 타임아웃은 문구가 아니라 인식의 제한 시간이다', () {
      expect(at(30), LoadingStage.cancellable);
      expect(at(120), LoadingStage.cancellable);
    });
  });

  group('문구 — 각 단계가 서로 다른 말을 한다', () {
    test('모든 단계에 비어 있지 않은 고유 문구가 있다', () {
      final messages = LoadingStage.values.map((s) => s.message).toList();
      expect(messages.every((m) => m.isNotEmpty), isTrue);
      expect(messages.toSet(), hasLength(LoadingStage.values.length));
    });
  });
}
