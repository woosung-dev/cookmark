// 메인 외길 페이지의 단일 상태 기계 — 화면 전환 0회(ADR-0001)의 대가로 상태가 여기 모인다.
import 'package:flutter/foundation.dart';

import '../data/storage.dart';
import '../domain/app_event.dart';
import '../domain/ingredient.dart';
import '../domain/session_state.dart';
import '../domain/vague_heuristic.dart';
import '../image/resize.dart';
import '../llm/llm_gateway.dart';

/// 단일 페이지 상태(ADR-0001). 제안은 #18에서 붙는다.
///
/// "세션 복원"은 별도 상태가 아니라 [MainController.restoreSession]이 지나온 체크리스트로
/// 되돌리는 경로다 — 사용자에게는 하던 화면이 그대로 보이는 게 전부다.
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

  /// 점선 칩으로 분리되는 뭉뚱그림 항목들(ADR-0002).
  List<Ingredient> get vagueItems => [
    for (final i in _ingredients)
      if (i.isVague) i,
  ];

  /// 매칭에 실제로 보낼 재료 — 해제된 것과 미치환 뭉뚱그림은 조용히 빠진다(ADR-0002).
  List<Ingredient> get matchableIngredients => [
    for (final i in _ingredients)
      if (i.goesToMatching) i,
  ];

  /// "자주 쓰는 재료" 칩 — 빈도 기반, 이미 체크리스트에 있는 건 뺀다(#15).
  List<String> get frequentIngredients {
    final present = {for (final i in _ingredients) i.name};
    return [
      for (final name in _storage.frequentIngredients(
        limit: 8 + present.length,
      ))
        if (!present.contains(name)) name,
    ].take(8).toList();
  }

  /// 브라우저를 닫았다 열면 마지막 재료 체크리스트로 돌아간다(#15).
  ///
  /// 인식 중이던 상태는 복원하지 않는다 — 그 호출은 이미 사라졌다.
  void restoreSession() {
    final session = _storage.readSession();
    if (session == null || session.ingredients.isEmpty) return;
    _ingredients = [...session.ingredients];
    _phase = MainPhase.checklist;
    notifyListeners();
  }

  /// 행 전체 탭 토글 — 재료 체크리스트의 유일한 제스처다(G1 #8).
  ///
  /// 삭제는 없다. 해제가 곧 매칭 제외다.
  Future<void> toggle(String name) async {
    final index = _ingredients.indexWhere((i) => i.name == name);
    if (index < 0) return;

    final next = _ingredients[index].copyWith(
      checked: !_ingredients[index].checked,
    );
    _ingredients[index] = next;
    notifyListeners();

    // 해제도 재체크도 각각 수동 수정 1회다(ADR-0003) — 산식은 파일럿 종료까지 불변.
    await _recordEdit(
      kind: next.checked ? EditKind.recheck : EditKind.uncheck,
      path: EditPath.row,
      name: name,
    );
  }

  /// 재료 직접 추가 — 하단 고정 추가 바(타이핑)와 칩 3종이 모두 여기로 들어온다.
  ///
  /// [path]가 경로를 가른다. 분석 단계에서 대안 산식을 재산하려면 이 해상도가 필요하다(ADR-0003).
  Future<void> addIngredient(String rawName, {required EditPath path}) async {
    final name = rawName.trim();
    if (name.isEmpty) return;

    final existing = _ingredients.indexWhere((i) => i.name == name);
    if (existing >= 0) {
      // 이미 있는 이름이면 새로 만들지 않고 체크만 되살린다 — 같은 재료가 두 줄이 되면 매칭이 오염된다.
      if (_ingredients[existing].checked) return;
      _ingredients[existing] = _ingredients[existing].copyWith(checked: true);
      notifyListeners();
      await _recordEdit(kind: EditKind.recheck, path: path, name: name);
      return;
    }

    _ingredients.add(Ingredient.added(name));
    notifyListeners();
    await _recordEdit(kind: EditKind.add, path: path, name: name);
  }

  /// 뭉뚱그림 칩의 인라인 치환 — "반찬통" → "멸치볶음, 김"(ADR-0002).
  ///
  /// 뭉뚱그림 항목은 사라지고 구체 재료들이 그 자리에 들어온다. 몇 개로 갈리든
  /// 1시퀀스 = 수동 수정 1회다(ADR-0003) — 사용자가 한 번 손을 댄 것이므로.
  Future<void> substituteVague(String vagueName, String raw) async {
    final index = _ingredients.indexWhere(
      (i) => i.name == vagueName && i.isVague,
    );
    if (index < 0) return;

    final replacements = parseSubstitution(raw);
    if (replacements.isEmpty) return;

    final existing = {for (final i in _ingredients) i.name};
    _ingredients
      ..removeAt(index)
      ..insertAll(index, [
        for (final name in replacements)
          if (!existing.contains(name)) Ingredient.added(name),
      ]);
    notifyListeners();

    await _recordEdit(
      kind: EditKind.substitute,
      path: EditPath.vagueChip,
      name: vagueName,
      extra: {'replacements': replacements},
    );
  }

  /// 뭉뚱그림 오탐 복귀 — 탭 1회로 일반 항목이 된다(ADR-0002).
  ///
  /// 휴리스틱이 클라이언트 추측이라 오탐이 구조적으로 가능하다. 성가시지 않아야 한다.
  Future<void> dismissVague(String name) async {
    final index = _ingredients.indexWhere((i) => i.name == name && i.isVague);
    if (index < 0) return;

    _ingredients[index] = _ingredients[index].copyWith(isVague: false);
    notifyListeners();

    await _recordEdit(
      kind: EditKind.vagueDismiss,
      path: EditPath.vagueChip,
      name: name,
    );
  }

  Future<void> _recordEdit({
    required EditKind kind,
    required EditPath path,
    required String name,
    Map<String, Object?> extra = const {},
  }) async {
    await _storage.appendEvent(
      AppEvent.checklistEdit(
        at: _now(),
        kind: kind,
        path: path,
        name: name,
        extra: extra,
      ),
    );
    await _saveSession();
  }

  Future<void> _saveSession() =>
      _storage.writeSession(SessionState(ingredients: _ingredients));

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
  Future<void> continueWithEmptyChecklist() async {
    _ingredients = [];
    _photo = null;
    _failure = null;
    _phase = MainPhase.checklist;
    notifyListeners();
    await _saveSession();
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
      // 게이트웨이가 준 목록을 그대로 들고 있으면 토글이 그 인스턴스를 건드린다 — 복사해서 소유한다.
      _ingredients = [...result.ingredients];
      _photo = null;
      _phase = MainPhase.checklist;
      await _saveSession();
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
