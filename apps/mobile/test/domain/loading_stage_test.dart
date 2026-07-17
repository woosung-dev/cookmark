// 로딩 단계식 문구의 경계 — G1 #8 확정값(0~3초 / 3~10초 / 10초 취소 등장).
import 'package:cookmark/domain/loading_stage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('stageFor', () {
    test('0초는 early다', () {
      expect(stageFor(Duration.zero), LoadingStage.early);
    });

    test('3초 정각은 아직 early다 — 경계는 초과 기준', () {
      expect(stageFor(const Duration(seconds: 3)), LoadingStage.early);
    });

    test('3초를 넘기면 mid로 간다', () {
      expect(
        stageFor(const Duration(seconds: 3, milliseconds: 1)),
        LoadingStage.mid,
      );
    });

    test('10초 정각은 아직 mid다', () {
      expect(stageFor(const Duration(seconds: 10)), LoadingStage.mid);
    });

    test('10초를 넘기면 slow로 가고 취소가 등장한다', () {
      final stage = stageFor(const Duration(seconds: 10, milliseconds: 1));
      expect(stage, LoadingStage.slow);
      expect(stage.showsCancel, isTrue);
    });
  });

  test('취소 버튼은 slow에서만 보인다 — 10초 전에는 이탈 유도를 하지 않는다', () {
    expect(LoadingStage.early.showsCancel, isFalse);
    expect(LoadingStage.mid.showsCancel, isFalse);
    expect(LoadingStage.slow.showsCancel, isTrue);
  });
}
