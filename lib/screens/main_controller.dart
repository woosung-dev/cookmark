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

/// 단일 페이지 상태 6종 중 #14가 다루는 4종. 제안·세션 복원 배너는 후속 티켓에서 붙는다.
enum MainState { onboarding, loading, checklist, failed }

/// 메인 페이지의 상태와 부작용(인식 호출·이벤트 적재)을 쥔다.
/// 위젯은 스토리지·LLM을 직접 만지지 않고 이 컨트롤러만 본다(코딩 스탠다드).
class MainController extends ChangeNotifier {
  MainController({
    required this.storage,
    required this.recognizer,
    ImagePicker? picker,
  }) : _picker = picker ?? ImagePicker() {
    _restoreSession();
  }

  final AppStorage storage;
  final IngredientRecognizer recognizer;
  final ImagePicker _picker;

  MainState _state = MainState.onboarding;
  List<Ingredient> _ingredients = const [];
  FailureReason? _failure;
  Uint8List? _photo;
  LoadingStage _stage = LoadingStage.scanning;
  Timer? _stageTimer;

  /// 진행 중인 인식을 취소했는지 — 늦게 도착한 응답이 화면을 되돌리지 못하게 막는다.
  int _attempt = 0;

  MainState get state => _state;
  List<Ingredient> get ingredients => List.unmodifiable(_ingredients);
  FailureReason? get failure => _failure;

  /// 스캔 시머를 얹을 사진. 로딩 중에만 있다.
  Uint8List? get photo => _photo;
  LoadingStage get stage => _stage;

  /// 첫 방문인지 — 온보딩 카피를 낼지 정한다.
  bool get isFirstVisit => storage.events.isEmpty;

  /// 브라우저를 닫았다 열어도 마지막 재료 체크리스트로 돌아온다.
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
      final result = await recognizer.recognize(resized);
      if (attempt != _attempt) return; // 취소됐거나 새 시도가 시작됨.

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
    } on RecognitionException catch (e) {
      if (attempt != _attempt) return;
      await storage.appendEvent(
        AppEvent(
          type: EventType.errorShown,
          at: DateTime.now(),
          data: {'reason': e.reason.name},
        ),
      );
      _failure = e.reason;
      _settle(MainState.failed);
    }
  }

  /// 10초 이후 등장하는 취소 — 기다림을 사용자가 끊을 수 있게 한다.
  void cancel() {
    _attempt++;
    _settle(MainState.onboarding);
  }

  /// 실패 카드의 "직접 입력으로 계속" — 빈 체크리스트 폴백으로 루프를 잇는다(G1 #8).
  void continueManually() {
    _ingredients = const [];
    _settle(MainState.checklist);
  }

  void _settle(MainState next) {
    _stageTimer?.cancel();
    _stageTimer = null;
    _photo = null;
    _state = next;
    notifyListeners();
  }

  /// 경과에 따라 문구를 바꾼다 — 30초(타임아웃 경계)에서 멈춘다.
  void _startStageTimer() {
    _stage = LoadingStage.scanning;
    _stageTimer?.cancel();
    final startedAt = DateTime.now();
    _stageTimer = Timer.periodic(const Duration(milliseconds: 500), (t) {
      final next = LoadingStage.forElapsed(
        DateTime.now().difference(startedAt),
      );
      if (next == LoadingStage.timedOut) {
        t.cancel();
        return;
      }
      if (next == _stage) return;
      _stage = next;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _stageTimer?.cancel();
    super.dispose();
  }
}
