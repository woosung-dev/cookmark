// 서버 도달 실패와 사용자 입력 실패가 화면에서 갈리는가 — 코호트 신고 경로의 입구다(#166).
//
// 왜 이 파일이 있나: 실패 카드가 네트워크·서버·파싱을 "인식에 실패했어요"로 띄우면 사용자가 읽는 뜻은
// "내 사진이 별로였나"이고 다음 행동은 조용한 이탈이다. 파일럿 2대에선 무해했지만(배우자가 파운더에게
// 직접 말한다) 코호트 원격에선 신고를 구조적으로 억제하고, 신고가 없으면 파운더가 서버가 죽은 걸 몰라
// roll-forward가 발동하지 않는다 — 되돌림 경로 전체가 종이가 된다.
import 'package:cookmark/llm/llm_gateway.dart';
import 'package:cookmark/ui/main_controller.dart';
import 'package:cookmark/ui/widgets/failure_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 사용자가 사진·재료를 고쳐도 어쩔 수 없는 실패 — 이 목록 자체가 #166의 결정이다.
/// 구현의 판정식을 그대로 불러 쓰면 분류가 바뀌어도 테스트가 따라 움직여 아무것도 지키지 못한다.
const _serverSide = {LlmFailureKind.error, LlmFailureKind.timeout};

void main() {
  Future<void> pumpCard(
    WidgetTester tester,
    LlmFailureKind kind,
    FailureStage stage, {
    VoidCallback? onRetry,
    VoidCallback? onContinueManually,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FailureCard(
              kind: kind,
              stage: stage,
              onRetry: onRetry ?? () {},
              onContinueManually: onContinueManually ?? () {},
            ),
          ),
        ),
      ),
    );
  }

  String headline(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('failure-headline'))).data!;

  final reportHint = find.byKey(const Key('failure-report-hint'));

  group('서버 도달 실패는 사용자 입력 실패와 다른 문구다 (#166)', () {
    for (final stage in FailureStage.values) {
      testWidgets('${stage.name} — 헤드라인이 갈린다', (tester) async {
        await pumpCard(tester, LlmFailureKind.error, stage);
        final server = headline(tester);

        await pumpCard(tester, LlmFailureKind.empty, stage);
        final user = headline(tester);

        expect(
          server,
          isNot(user),
          reason: '같은 문구면 사용자가 서버 장애를 "내 사진이 별로였나"로 읽는다',
        );
      });
    }

    testWidgets('인식 서버 실패는 사진 탓으로 읽히지 않는다', (tester) async {
      await pumpCard(tester, LlmFailureKind.error, FailureStage.recognition);

      expect(find.text('인식에 실패했어요.'), findsNothing);
      expect(find.text('재료를 하나도 찾지 못했어요.'), findsNothing);
      expect(find.text('사진이 어두워서 잘 안 보여요.'), findsNothing);
    });
  });

  group('신고 유도 — 서버 문제일 때만 뜬다', () {
    for (final stage in FailureStage.values) {
      for (final kind in LlmFailureKind.values) {
        testWidgets('${stage.name} · ${kind.name}', (tester) async {
          await pumpCard(tester, kind, stage);

          expect(
            reportHint,
            _serverSide.contains(kind) ? findsOneWidget : findsNothing,
            reason: _serverSide.contains(kind)
                ? '서버 쪽 실패인데 신고 유도가 없으면 장애가 아무에게도 전달되지 않는다'
                : '사용자 입력 실패까지 신고를 유도하면 진짜 장애 신고가 소음에 묻힌다',
          );
        });
      }
    }

    testWidgets('신고 유도는 사용자가 무엇을 해야 하는지 말한다', (tester) async {
      await pumpCard(tester, LlmFailureKind.error, FailureStage.recognition);

      expect(find.textContaining('알려주세요'), findsOneWidget);
    });
  });

  group('어느 실패든 루프가 이어진다 — 막다른 화면이 없다 (G1 #8)', () {
    for (final stage in FailureStage.values) {
      for (final kind in LlmFailureKind.values) {
        testWidgets('${stage.name} · ${kind.name}의 탈출구 둘', (tester) async {
          var retried = 0;
          var continued = 0;
          await pumpCard(
            tester,
            kind,
            stage,
            onRetry: () => retried++,
            onContinueManually: () => continued++,
          );

          await tester.tap(find.byKey(const Key('failure-retry')));
          await tester.tap(find.byKey(const Key('failure-manual')));

          expect(retried, 1);
          expect(continued, 1);
        });
      }
    }
  });
}
