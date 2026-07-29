// 신고 유도 한 줄 — 서버 쪽 실패 표면이 공유한다. 파운더가 원격 코호트의 장애를 아는 유일한 경로다.
//
// 왜 위젯으로 뽑나 — 이 문구는 #166이 인식·매칭 카드에 넣었고 #127이 저장·하이드레이트 카드로
// 넓혔다. 세 곳에 리터럴로 복제하면 문구가 갈리고, 갈리면 신고 경로가 갈린다(스펙 #161 §G가
// 여는 것은 문장 하나가 아니라 "사용자가 파운더에게 말하게 되는 사건"이다).
//
// 어디에 붙일지는 붙이는 쪽이 정한다 — 이 위젯은 판정하지 않는다. LLM 경계는 사용자 입력이
// 원인인 실패(empty·lowQuality)가 있어 `LlmFailureBlame.isServerSide`로 가르고, 레시피 북
// 경계는 그런 값이 아예 없어 무조건 붙인다. 판정을 여기로 끌어오면 두 축이 한 곳에서 뭉친다.
import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';

class ReportHint extends StatelessWidget {
  const ReportHint({super.key});

  @override
  Widget build(BuildContext context) {
    // 같은 크기·굵기면 위 줄들과 평평하게 쌓여 눈이 그냥 흘린다. 작게·굵게로 위계를 만든다
    // (DESIGN.md §3). muted로 낮추지 않는 이유 — 이 줄이 카드의 용건이다.
    return Text(
      '계속 이러면 만든 사람에게 카톡으로 알려주세요.',
      style: AppTypography.footnote.copyWith(fontWeight: FontWeight.w600),
    );
  }
}
