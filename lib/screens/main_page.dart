// 메인 외길 화면 — 업로드→로딩→재료 체크리스트를 한 세로 페이지의 섹션으로 잇는다(ADR-0001)
import 'package:flutter/material.dart';

import '../llm/recognizer.dart';
import '../widgets/checklist_section.dart';
import '../widgets/failure_card.dart';
import '../widgets/recognition_section.dart';
import '../widgets/upload_zone.dart';
import 'main_controller.dart';

/// 앱의 두 화면 중 하나. 코어 루프 전체가 여기서 화면 전환 0회로 일어난다.
///
/// #14 구간은 상태 4종(온보딩·로딩·체크리스트·실패)까지다 —
/// 제안은 후속 티켓에서 이 switch에 붙는다.
///
/// 헤더의 레시피 북 링크(ADR-0001의 유일한 진입점)는 #17이 레시피 북 화면과 함께 붙인다 —
/// 갈 곳 없는 링크를 파일럿에 먼저 내보내지 않는다.
class MainPage extends StatelessWidget {
  const MainPage({required this.controller, super.key});

  final MainController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('냉파'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1),
        ),
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => switch (controller.state) {
            MainState.onboarding => UploadZone(
              onPick: controller.pickAndRecognize,
            ),
            MainState.loading => RecognitionSection(
              photo: controller.photo,
              stage: controller.stage,
              onCancel: controller.cancel,
            ),
            MainState.checklist => ChecklistSection(
              ingredients: controller.ingredients,
            ),
            MainState.failed => Padding(
              padding: const EdgeInsets.all(16),
              child: FailureCard(
                reason: controller.failure ?? FailureReason.server,
                onRetry: controller.pickAndRecognize,
              ),
            ),
          },
        ),
      ),
    );
  }
}
