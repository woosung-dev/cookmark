// 메인 외길 페이지의 단일 상태 기계 — 화면 전환 0회(ADR-0001)의 대가로 상태가 여기 모인다.
import 'package:flutter/foundation.dart';

import '../data/storage.dart';
import '../domain/app_event.dart';
import '../domain/ingredient.dart';
import '../image/resize.dart';
import '../llm/llm_gateway.dart';

/// 단일 페이지 상태 6종 중 이 티켓(#14) 구간 — 온보딩/로딩/체크리스트/에러.
/// 제안은 #18, 세션 복원은 #15에서 붙는다.
enum MainPhase { upload, recognizing, checklist, failed }

class MainController extends ChangeNotifier {
  MainController(this._gateway, this._storage, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final LlmGateway _gateway;
  final Storage _storage;

  /// 테스트가 시간을 고정할 수 있게 — 이벤트 타임스탬프는 분석의 기준선이라 결정적이어야 한다.
  final DateTime Function() _now;

  MainPhase get phase => _phase;
  MainPhase _phase = MainPhase.upload;

  /// 확정 전 재료 후보. 순서는 인식이 준 그대로 두고, 화면이 confidence로 묶는다.
  List<Ingredient> get ingredients => List.unmodifiable(_ingredients);
  List<Ingredient> _ingredients = [];

  /// 로딩 중 스캔 시머를 얹을 사진. 인식이 끝나면 버린다 — 사진은 보관하지 않는다(스펙 Out of scope).
  Uint8List? get photo => _photo;
  Uint8List? _photo;

  LlmFailureKind? get failure => _failure;
  LlmFailureKind? _failure;

  /// 인식이 시작된 시각 — 로딩 단계식 문구가 여기서 경과를 잰다.
  DateTime? get recognizeStartedAt => _recognizeStartedAt;
  DateTime? _recognizeStartedAt;

  Uint8List? _lastResizedPhoto;

  /// 사진 1장 → 리사이즈 → 인식 → 재료 체크리스트. 코어 루프의 시작이다.
  Future<void> uploadPhoto(Uint8List original) async {
    final resized = await resizeForRecognition(original);
    _photo = resized.bytes;
    _lastResizedPhoto = resized.bytes;
    await _storage.appendEvent(
      AppEvent.photoUpload(
        at: _now(),
        bytes: resized.bytes.length,
        width: resized.width,
      ),
    );
    await _recognize(resized.bytes);
  }

  /// 실패 인라인 카드의 "다시 시도" — 같은 사진으로 다시 부른다(리사이즈는 건너뛴다).
  Future<void> retryRecognition() async {
    final photo = _lastResizedPhoto;
    if (photo == null) return;
    await _recognize(photo);
  }

  /// 실패 인라인 카드의 "직접 입력으로 계속" — 빈 체크리스트 폴백(G1 #8, 막다른 화면 없음).
  void continueWithEmptyChecklist() {
    _ingredients = [];
    _photo = null;
    _failure = null;
    _phase = MainPhase.checklist;
    notifyListeners();
  }

  Future<void> _recognize(Uint8List jpegBytes) async {
    _phase = MainPhase.recognizing;
    _failure = null;
    _recognizeStartedAt = _now();
    notifyListeners();

    try {
      final result = await _gateway.recognize(jpegBytes);
      final latency = _now().difference(_recognizeStartedAt!);
      await _storage.appendEvent(
        AppEvent.recognitionDone(
          at: _now(),
          latency: latency,
          usage: result.usage,
          count: result.ingredients.length,
        ),
      );
      _ingredients = result.ingredients;
      _photo = null;
      _phase = MainPhase.checklist;
    } on LlmFailure catch (e) {
      await _storage.appendEvent(
        AppEvent.errorShown(
          at: _now(),
          kind: e.kind.name,
          stage: 'recognition',
        ),
      );
      _failure = e.kind;
      _phase = MainPhase.failed;
    }
    notifyListeners();
  }
}
