// 메인 외길 페이지의 단일 상태 기계 — 화면 전환 0회(ADR-0001)의 대가로 상태가 여기 모인다.
import 'package:flutter/foundation.dart';

import '../data/storage.dart';
import '../domain/app_event.dart';
import '../domain/ingredient.dart';
import '../domain/session_state.dart';
import '../domain/suggestion.dart';
import '../domain/in_app_browser.dart';
import '../domain/vague_heuristic.dart';
import '../image/resize.dart';
import '../llm/llm_gateway.dart';
import '../platform/user_agent.dart';
import 'recipe_book_controller.dart';

/// 단일 페이지 상태(ADR-0001).
///
/// "세션 복원"은 별도 상태가 아니라 [MainController.restoreSession]이 지나온 체크리스트로
/// 되돌리는 경로다 — 사용자에게는 하던 화면이 그대로 보이는 게 전부다.
enum MainPhase { upload, recognizing, checklist, matching, suggestions, failed }

/// 실패가 어느 단계에서 났는지 — 인라인 카드가 어느 섹션에 붙을지 정한다(G1 #8).
enum FailureStage { recognition, matching }

class MainController extends ChangeNotifier {
  MainController(
    this._gateway,
    this._storage, {
    DateTime Function()? now,
    String Function()? userAgent,
  }) : _now = now ?? DateTime.now,
       _userAgent = userAgent ?? currentUserAgent;

  final LlmGateway _gateway;
  final Storage _storage;

  /// 테스트가 시간을 고정할 수 있게 — 이벤트 타임스탬프는 분석의 기준선이라 결정적이어야 한다.
  final DateTime Function() _now;

  /// 테스트가 인앱 브라우저를 흉내 낼 수 있게 — 브라우저를 진짜로 띄울 수는 없다.
  final String Function() _userAgent;

  /// 카톡 인앱 브라우저에서 열렸는가 — 그러면 상시 경고 배너가 뜬다(#21).
  ///
  /// 닫을 수 없다. 여기서 쓰면 2주치 기록이 통째로 날아갈 수 있다.
  late final bool showsInAppBrowserWarning = isKakaoInAppBrowser(_userAgent());

  /// 첫 인식 결과 위에 1회성으로 뜨는 기대 세팅 문구(B 이식, G1 #8).
  ///
  /// 영속 플래그는 첫 인식이 끝나는 순간 찍고, 이번 화면에는 이 메모리 플래그로 계속 보여준다 —
  /// 곧바로 영속 플래그를 읽으면 그리자마자 사라진다.
  bool get showsExpectationNote => _showExpectationNote;
  bool _showExpectationNote = false;

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

  /// 실패가 인식에서 났는지 매칭에서 났는지 — 인라인 카드의 문구와 재시도 대상이 갈린다.
  FailureStage get failureStage => _failureStage;
  FailureStage _failureStage = FailureStage.recognition;

  /// 화면에 올라간 "오늘 할 3개".
  List<Suggestion> get suggestions => List.unmodifiable(_suggestions);
  List<Suggestion> _suggestions = [];

  /// 부족 4개 이상이라 제외된 메뉴 수 — 투명성 줄이 이걸 말한다(스펙 #13).
  int get excludedCount => _excludedCount;
  int _excludedCount = 0;

  /// 제안이 뜬 뒤 재료를 손대면 아래 제안이 낡는다(ADR-0001).
  ///
  /// 낡은 채로 발생한 이벤트에는 stale 플래그가 붙어 성공 지표 2 집계에서 분리된다 —
  /// 화면에서 카드를 치우지 않는 대신 로그 층위에서 순도를 지킨다.
  bool get isStale => _stale;
  bool _stale = false;

  /// 제안이 뜨면 체크리스트는 요약 한 줄로 접힌다(G1 #8). 탭하면 다시 펼쳐 손볼 수 있다.
  bool get checklistExpanded => _checklistExpanded;
  bool _checklistExpanded = true;

  void toggleChecklistExpanded() {
    _checklistExpanded = !_checklistExpanded;
    notifyListeners();
  }

  /// "이거 했어요"를 눌렀지만 아직 5초 실행취소가 살아 있는 제안.
  Suggestion? get pendingCooked => _pendingCooked;
  Suggestion? _pendingCooked;

  /// 인식이 시작된 시각 — 로딩 단계식 문구가 여기서 경과를 잰다.
  DateTime? get recognizeStartedAt => _recognizeStartedAt;
  DateTime? _recognizeStartedAt;

  Uint8List? _lastResizedPhoto;

  /// 레시피 북이 비어 있고 아직 건너뛰지 않았으면 첫 방문 상태다 — 업로드 존 자리에 온보딩 카드가 온다.
  ///
  /// 별도 화면이 아니라 메인의 한 상태다(G1 #8).
  bool get showsOnboarding =>
      !_onboardingSkipped && _storage.readRecipes().isEmpty;
  bool _onboardingSkipped = false;

  /// 건너뛰기 — 빈 레시피 북으로도 루프는 돈다. 대신 넛지 칩이 상시로 남는다.
  void skipOnboarding() {
    _onboardingSkipped = true;
    notifyListeners();
  }

  /// 3개 미만이면 넛지 칩을 띄운다(G1 #8).
  bool get showsRecipeNudge =>
      _storage.readRecipes().length < trustedRecipeGoal;

  int get recipeCount => _storage.readRecipes().length;

  /// 레시피 북 재료 중 지금 체크리스트에 없는 것 — 강조 칩으로 뜬다(B 이식, G1 #8).
  ///
  /// 질문 2(저장 레시피가 실제 선택을 바꾸는가)의 검증 확률을 직접 올리는 장치다 —
  /// 저장 레시피와 연결될 재료를 놓치지 않게 한다.
  List<String> get unrecognizedFromRecipeBook {
    final present = {for (final i in _ingredients) i.name};
    final seen = <String>{};
    return [
      for (final recipe in _storage.readRecipes())
        for (final name in recipe.ingredients)
          if (!present.contains(name) && seen.add(name)) name,
    ];
  }

  /// 레시피 북이 바뀐 뒤 화면을 다시 그리게 한다 — 스토리지에서 바로 읽으므로 알림만 주면 된다.
  void refresh() => notifyListeners();

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

  /// 확정 재료를 레시피 북과 맞춰 "오늘 할 3개"를 얻는다 — 코어 루프의 심장(#18).
  Future<void> requestSuggestions() async {
    final ingredients = [for (final i in matchableIngredients) i.name];
    if (ingredients.isEmpty) return;

    // 이미 제안이 있는데 다시 부르는 건 "다시 제안"이다 — 낡은 걸 갱신하는 행위(ADR-0001).
    if (_suggestions.isNotEmpty) {
      await _storage.appendEvent(
        AppEvent.rematch(at: _now(), previousCount: _suggestions.length),
      );
    }

    final recipes = _storage.readRecipes();
    _phase = MainPhase.matching;
    _failure = null;
    _matchStartedAt = _now();
    notifyListeners();

    try {
      final result = await _gateway.match(
        ingredients: ingredients,
        recipes: recipes,
      );
      // 부족 4개 이상 제외와 3개 상한은 클라이언트가 한다 — 제외 수를 집계해야 하므로.
      final selection = selectSuggestions(result.suggestions);
      final latency = _now().difference(_matchStartedAt!);

      await _storage.appendEvent(
        AppEvent.matchingDone(
          at: _now(),
          latency: latency,
          usage: result.usage,
          shownCount: selection.shown.length,
          excludedCount: selection.excludedCount,
        ),
      );
      await _storage.appendEvent(
        AppEvent.suggestionsShown(at: _now(), suggestions: selection.shown),
      );

      _suggestions = selection.shown;
      _excludedCount = selection.excludedCount;
      // 갓 뽑은 제안이다 — 낡음이 여기서 리셋된다.
      _stale = false;
      // 제안이 뜨면 체크리스트는 요약 한 줄로 접힌다(G1 #8).
      _checklistExpanded = false;
      _phase = MainPhase.suggestions;
    } on LlmFailure catch (e) {
      await _storage.appendEvent(
        AppEvent.errorShown(at: _now(), kind: e.kind.name, stage: 'matching'),
      );
      _failure = e.kind;
      _failureStage = FailureStage.matching;
      _phase = MainPhase.failed;
    }
    notifyListeners();
  }

  /// "레시피 보기" — 저장 카드만 가진다. 원본은 새 탭으로 열고, 여는 것 자체가 선택 이벤트다.
  Future<void> openRecipe(Suggestion suggestion) async {
    if (suggestion.recipeUrl == null) return;
    await _storage.appendEvent(
      AppEvent.suggestionOpened(
        at: _now(),
        suggestion: suggestion,
        stale: _stale,
      ),
    );
  }

  /// "이거 했어요" — 성공 지표 2의 판정 장치. 5초 실행취소가 열린다.
  Future<void> markCooked(Suggestion suggestion) async {
    _pendingCooked = suggestion;
    notifyListeners();
    await _storage.appendEvent(
      AppEvent.cooked(at: _now(), suggestion: suggestion, stale: _stale),
    );
  }

  /// 5초 안에 되돌렸다. 취소도 이벤트다 — 실수인지 마음이 바뀐 건지는 분석이 판단한다.
  Future<void> undoCooked() async {
    final suggestion = _pendingCooked;
    if (suggestion == null) return;
    _pendingCooked = null;
    notifyListeners();
    await _storage.appendEvent(
      AppEvent.cookedUndo(at: _now(), suggestion: suggestion, stale: _stale),
    );
  }

  /// 실행취소 창이 닫혔다 — 되돌릴 수 없다.
  void dismissUndo() {
    if (_pendingCooked == null) return;
    _pendingCooked = null;
    notifyListeners();
  }

  /// 매칭 로딩 문구에 쓰는 수 — "레시피 북 N개와 맞춰보는 중".
  int get matchingRecipeCount => _storage.readRecipes().length;

  DateTime? _matchStartedAt;

  /// 체크리스트로 돌아간다 — 제안이 마음에 안 들면 재료부터 다시 본다.
  void backToChecklist() {
    _phase = MainPhase.checklist;
    notifyListeners();
  }

  Future<void> _recordEdit({
    required EditKind kind,
    required EditPath path,
    required String name,
    Map<String, Object?> extra = const {},
  }) async {
    // 아래에 제안이 떠 있는데 재료를 손댔다면 그 제안은 낡은 재고로 뽑힌 것이다(ADR-0001).
    if (_suggestions.isNotEmpty && !_stale) {
      _stale = true;
      notifyListeners();
    }

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
      // 첫 인식 결과에만 붙는다. 이 앱은 인식이 틀리는 걸 전제로 설계됐고(재료 체크리스트가 그 장치다),
      // 사용자가 그걸 모르면 첫 오인식에서 앱을 접는다.
      if (!_storage.readExpectationNoteSeen()) {
        _showExpectationNote = true;
        await _storage.markExpectationNoteSeen();
      }

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
      _failureStage = FailureStage.recognition;
      _phase = MainPhase.failed;
    }
    notifyListeners();
  }
}
