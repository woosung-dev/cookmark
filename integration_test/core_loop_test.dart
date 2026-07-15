// 코어 루프 E2E — 검증의 정본(코딩 스탠다드). LLM 경계에 페이크를 주입해 결정적으로 돌린다.
import 'dart:typed_data';

import 'package:cookmark/data/app_storage.dart';
import 'package:cookmark/llm/fake_recognizer.dart';
import 'package:cookmark/llm/recognizer.dart';
import 'package:cookmark/main.dart';
import 'package:cookmark/models/app_event.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// 사진 선택 다이얼로그를 넘기기 위한 대역. 앱에 seam을 추가하지 않고
  /// image_picker 플러그인 자체의 테스트 훅만 바꾼다.
  late Uint8List photoBytes;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    photoBytes = img.encodeJpg(img.Image(width: 1600, height: 1200));
    ImagePickerPlatform.instance = _FakePickerPlatform(() => photoBytes);
  });

  Future<AppStorage> pumpApp(
    WidgetTester tester, {
    IngredientRecognizer recognizer = const FakeRecognizer(),
    Duration recognitionTimeout = kRecognitionTimeout,
  }) async {
    // 파일럿 타깃은 모바일 브라우저다 — 데스크톱 기본 뷰포트로 재면 실제로 화면
    // 밖에 있는 요소가 테스트에서만 닿는다.
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final storage = await AppStorage.open();
    await tester.pumpWidget(
      CookmarkApp(
        storage: storage,
        recognizer: recognizer,
        recognitionTimeout: recognitionTimeout,
      ),
    );
    await tester.pumpAndSettle();
    return storage;
  }

  testWidgets('사진 1장을 올리면 재료 체크리스트가 뜬다 — 코어 관통', (tester) async {
    final storage = await pumpApp(tester);

    // 온보딩 — 업로드 존이 입구다.
    expect(find.byKey(const Key('upload-button')), findsOneWidget);
    expect(find.byKey(const Key('checklist')), findsNothing);

    await tester.tap(find.byKey(const Key('upload-button')));
    await tester.pumpAndSettle();

    // 체크리스트 — 페이크 fixture의 재료가 화면에 보인다.
    expect(find.byKey(const Key('checklist')), findsOneWidget);
    expect(find.text('대파'), findsOneWidget);
    expect(find.text('두부'), findsOneWidget);

    // 이벤트 로그 — 업로드와 인식 완료가 지연·토큰·원가와 함께 남는다.
    final types = storage.events.map((e) => e.type).toList();
    expect(types, contains(EventType.photoUploaded));
    expect(types, contains(EventType.recognitionCompleted));

    final done = storage.events.firstWhere(
      (e) => e.type == EventType.recognitionCompleted,
    );
    expect(done.data['latencyMs'], isNotNull);
    expect(done.data['inputTokens'], 1157);
    expect(done.data['outputTokens'], 295);
    expect(done.data['thinkingTokens'], 0);
    expect(done.data['estimatedCostUsd'], 0.00073);
    // 모델명이 없으면 이 행이 어떤 모델의 원가인지 사후에 댈 수 없다.
    expect(done.data['model'], 'gemini-3.1-flash-lite');
  });

  testWidgets('confidence 3단 초기 상태로 렌더된다 (ADR-0003)', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('upload-button')));
    await tester.pumpAndSettle();

    // low는 "확실하지 않아요" 흐린 그룹으로 분리된다.
    expect(find.byKey(const Key('uncertain-group-header')), findsOneWidget);
    expect(find.text('트러플'), findsOneWidget);

    // medium은 체크된 채로 물음표 점이 붙는다 — fixture의 medium은 3개.
    expect(find.byKey(const Key('medium-dot')), findsNWidgets(3));
  });

  testWidgets('새로고침해도 재료 체크리스트와 이벤트가 남는다 — 세션 복원', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('upload-button')));
    await tester.pumpAndSettle();
    expect(find.text('대파'), findsOneWidget);

    // 앱을 새로 띄운다 = 브라우저를 닫았다 여는 것과 같다(스토리지는 그대로).
    final reopened = await pumpApp(tester);

    expect(find.byKey(const Key('checklist')), findsOneWidget);
    expect(find.text('대파'), findsOneWidget);
    expect(
      reopened.events.where((e) => e.type == EventType.photoUploaded),
      hasLength(1),
    );
  });

  testWidgets('인식 실패는 그 자리의 인라인 카드로 처리한다 — 막다른 에러 화면 없음', (tester) async {
    final storage = await pumpApp(
      tester,
      recognizer: const FakeRecognizer(failWith: FailureReason.empty),
    );

    await tester.tap(find.byKey(const Key('upload-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('failure-card')), findsOneWidget);
    expect(find.text('재료를 찾지 못했어요'), findsOneWidget);
    expect(find.byKey(const Key('retry-button')), findsOneWidget);
    expect(storage.events.map((e) => e.type), contains(EventType.errorShown));
  });

  testWidgets('인식이 제한 시간을 넘기면 타임아웃 카드가 뜬다 (AC — 30초)', (tester) async {
    await pumpApp(
      tester,
      // 제 타이머가 없는 페이크 — 제한 시간은 호출 경계가 지킨다.
      recognizer: const FakeRecognizer(delay: Duration(seconds: 90)),
      recognitionTimeout: const Duration(seconds: 1),
    );

    await tester.tap(find.byKey(const Key('upload-button')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('failure-card')), findsOneWidget);
    expect(find.text('시간이 너무 오래 걸렸어요'), findsOneWidget);
  });

  testWidgets('인식이 길어지면 문구가 바뀌고 10초에 취소가 등장한다', (tester) async {
    await pumpApp(
      tester,
      recognizer: const FakeRecognizer(delay: Duration(seconds: 20)),
    );

    await tester.tap(find.byKey(const Key('upload-button')));
    // 사진 선택·바이트 읽기의 비동기 구간을 흘려보낸다(pumpAndSettle은 20초 페이크를 기다려 버린다).
    await tester.pump();
    await tester.pump();

    // 0~3초 — 첫 문구, 취소 없음.
    expect(find.text('사진에서 재료를 찾고 있어요'), findsOneWidget);
    expect(find.byKey(const Key('cancel-button')), findsNothing);

    // 3~10초 — 문구가 바뀐다.
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('재료를 하나씩 확인하는 중이에요'), findsOneWidget);
    expect(find.byKey(const Key('cancel-button')), findsNothing);

    // 10초 — 취소가 등장한다.
    await tester.pump(const Duration(seconds: 7));
    expect(find.byKey(const Key('cancel-button')), findsOneWidget);

    // 취소하면 업로드 존으로 돌아간다.
    await tester.ensureVisible(find.byKey(const Key('cancel-button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('cancel-button')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('upload-button')), findsOneWidget);
  });
}

class _FakePickerPlatform extends ImagePickerPlatform {
  _FakePickerPlatform(this.bytes);

  final Uint8List Function() bytes;

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async =>
      XFile.fromData(bytes(), mimeType: 'image/jpeg', name: 'fridge.jpg');
}
