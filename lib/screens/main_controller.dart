// 메인 외길의 단일 페이지 상태 기계 — 화면 전환 없이 상태만 바꾼다(ADR-0001)
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../data/app_storage.dart';
import '../image/resize.dart';
import '../llm/recognizer.dart';
import '../models/app_event.dart';
import '../models/ingredient.dart';
import 'loading_stage.dart';

/// 단일 페이지 상태 6종 중 #14가 다루는 4종. 제안은 후속 티켓에서 붙는다.
enum MainState { onboarding, loading, checklist, failed }

/// 메인 페이지의 상태와 부작용(인식 호출·이벤트 적재)을 쥔다.
/// 위젯은 스토리지·LLM을 직접 만지지 않고 이 컨트롤러만 본다(코딩 스탠다드).
class MainController extends ChangeNotifier {
  MainController({
    required this.storage,
    required this.recognizer,
    this.recognitionTimeout = kRecognitionTimeout,
    ImagePicker? picker,
  }) : _picker = picker ?? ImagePicker() {
    _restoreSession();
  }

  final AppStorage storage;
  final IngredientRecognizer recognizer;

  /// 인식 제한 시간. 기본은 [kRecognitionTimeout](30초)이고, 테스트만 줄여 쓴다.
  final Duration recognitionTimeout;

  final ImagePicker _picker;

  MainState _state = MainState.onboarding;
  List<Ingredient> _ingredients = const [];
  FailureReason? _failure;
  Uint8List? _photo;
  LoadingStage _stage = LoadingStage.justStarted;
  Timer? _stageTimer;

  /// 시도 일련번호 — 취소했거나 새로 시작한 뒤 늦게 도착한 응답이 화면을 되돌리지 못하게 막는다.
  int _attempt = 0;

  MainState get state => _state;
  List<Ingredient> get ingredients => List.unmodifiable(_ingredients);
  FailureReason? get failure => _failure;

  /// 스캔 시머를 얹을 사진. 로딩 중에만 있다 — 인식 후에는 보관하지 않는다(스펙 #13).
  Uint8List? get photo => _photo;
  LoadingStage get stage => _stage;

  /// 브라우저를 닫았다 열어도 마지막 재료 체크리스트로 돌아온다.
  ///
  /// 스펙상 US 23·상태 "세션 복원"이고 #14의 AC는 아니다 — 스토리지 경계를 세우며
  /// 딸려 온 절반 구현이다. "다시 제안" 배너와 stale 플래그는 #15·#19가 붙인다.
  void _restoreSession() {
    final restored = storage.session;
    if (restored.isEmpty) return;
    _ingredients = restored;
    _state = MainState.checklist;
  }

  /// 사진 1장을 골라 재료 인식까지 관통한다 — 코어 루프의 시작.
  Future<void> pickAndRecognize() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return; // 사용자가 고르지 않고 닫음 — 상태를 건드리지 않는다.

    await recognizeBytes(await picked.readAsBytes());
  }

  /// 바이트를 받아 인식한다. 사진 선택을 거치지 않는 경로(E2E·재시도)가 쓴다.
  @visibleForTesting
  Future<void> recognizeBytes(Uint8List bytes) async {
    final attempt = ++_attempt;

    _state = MainState.loading;
    _failure = null;
    _photo = bytes;
    _startStageTimer();
    notifyListeners();

    await storage.appendEvent(
      AppEvent(type: EventType.photoUploaded, at: DateTime.now()),
    );

    try {
      // 리사이즈는 전송 전 클라이언트에서 — 긴 변 768px(지연 레버).
      final resized = resizeForRecognition(bytes);

      // 제한 시간은 구현이 아니라 여기서 건다 — 어떤 recognizer를 끼워도 30초 약속이 지켜진다.
      final result = await recognizer
          .recognize(resized)
          .timeout(recognitionTimeout);
      if (attempt != _attempt) return;

      await storage.appendEvent(
        AppEvent(
          type: EventType.recognitionCompleted,
          at: DateTime.now(),
          data: {
            ...result.usage.toEventData(),
            'ingredientCount': result.ingredients.length,
          },
        ),
      );

      _ingredients = result.ingredients;
      await storage.saveSession(_ingredients);
      _settle(MainState.checklist);
    } on TimeoutException {
      await _fail(attempt, FailureReason.timeout);
    } on ImageDecodeException {
      await _fail(attempt, FailureReason.lowQuality);
    } on RecognitionException catch (e) {
      await _fail(attempt, e.reason);
    }
  }

  Future<void> _fail(int attempt, FailureReason reason) async {
    if (attempt != _attempt) return;
    await storage.appendEvent(
      AppEvent(
        type: EventType.errorShown,
        at: DateTime.now(),
        data: {'reason': reason.name},
      ),
    );
    _failure = reason;
    _settle(MainState.failed);
  }

  /// 10초 이후 등장하는 취소 — 기다림을 사용자가 끊을 수 있게 한다.
  void cancel() {
    _attempt++;
    _settle(MainState.onboarding);
  }

  void _settle(MainState next) {
    _stageTimer?.cancel();
    _stageTimer = null;
    _photo = null;
    _state = next;
    notifyListeners();
  }

  /// 경과에 따라 문구를 바꾼다. 마지막 단계에 닿으면 더 볼 일이 없으므로 멈춘다.
  void _startStageTimer() {
    _stage = LoadingStage.justStarted;
    _stageTimer?.cancel();
    final startedAt = DateTime.now();
    _stageTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      final next = LoadingStage.forElapsed(
        DateTime.now().difference(startedAt),
      );
      if (next == _stage) return;
      _stage = next;
      notifyListeners();
      if (next == LoadingStage.values.last) t.cancel();
    });
  }

  @override
  void dispose() {
    _stageTimer?.cancel();
    super.dispose();
  }
}
