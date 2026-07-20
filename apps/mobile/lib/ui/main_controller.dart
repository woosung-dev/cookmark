// 메인 외길 페이지의 단일 상태 기계 — 화면 전환 0회(ADR-0001)의 대가로 상태가 여기 모인다.
import 'package:flutter/foundation.dart';

import '../data/storage.dart';
import '../domain/app_event.dart';
import '../domain/ingredient.dart';
import '../domain/session_state.dart';
import '../domain/suggestion.dart';
import '../domain/debug_metrics.dart';
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

  /// 측정 푸터는 파운더가 앱바 타이틀을 롱프레스한 세션에만 존재한다(ADR-0004 단일맹검).
  ///
  /// 배우자에게 계측을 노출하면 P2 킬 기준 측정이 왜곡되고, 한 번 공개하면 되돌릴 수 없다.
  /// 영속하지 않는 것이 계약이다 — 앱을 다시 띄우면 도로 숨어 잔상이 남지 않는다.
  bool get showsDebugFooter => _showsDebugFooter;
  bool _showsDebugFooter = false;

  /// 숨은 제스처의 유일한 진입점(#143). 다시 누르면 도로 닫힌다.
  void toggleDebugFooter() {
    _showsDebugFooter = !_showsDebugFooter;
    notifyListeners();
  }

  /// D0 직전 기록 초기화 — 관통 테스트가 남긴 것을 지운다(#144, 절차 #41).
  ///
  /// 계약은 한 문장이다 — **초기화 후의 앱은 레시피만 남은 기기에서 처음 켠 것과 구별되지 않는다.**
  /// 영속층은 [Storage.clearPilotRecord]가 지우고, 여기서는 그 위에 얹힌 메모리 상태를 되감는다.
  /// 영속 키만 지우면 화면에는 관통 테스트의 체크리스트·제안이 그대로 남아 리셋이 눈에 보이게 깨진다.
  ///
  /// 단 하나의 예외가 [showsDebugFooter]다 — 파운더는 초기화 직후 푸터에서 "이벤트 0"을 확인해야
  /// 한다. 같이 닫으면 확인하려고 제스처를 다시 해야 하고, 애초에 영속되지 않는 세션 상태라
  /// 보존 경계와 충돌하지도 않는다.
  ///
  /// ⚠️ 루프 상태를 비우는 코드가 [startNewPhoto]와 겹친다. **합치지 않은 건 의도**다 —
  /// 그쪽은 빈 세션을 도로 쓰고(여긴 키가 없어야 한다) 1회성 문구·온보딩을 안 건드린다.
  /// 대가로 **새 루프 필드를 추가하면 두 곳 다 비워야 한다.**
  Future<void> resetPilotRecord() async {
    await _storage.clearPilotRecord();

    // 날고 있는 인식·매칭 응답을 버린다 — 뒤늦게 돌아와 방금 비운 화면을 덮지 않게.
    // 세대 가드는 **화면만** 막는다. 이벤트까지 막는 건 아래 _recordEpoch다.
    _abandonInFlightRecognition();
    _matchGeneration++;
    _recordEpoch++;

    _ingredients = [];
    _photo = null;
    _lastResizedPhoto = null;
    _recognizeStartedAt = null;
    _suggestions = [];
    _excludedCount = 0;
    _stale = false;
    _checklistExpanded = true;
    _pendingCooked = null;
    _failure = null;
    _failureStage = FailureStage.recognition;
    _showExpectationNote = false;
    // 영속 플래그를 지웠으므로 온보딩도 갓 부팅 상태로 — 레시피가 3개 미만이면 다시 안내한다.
    _onboardingSkipped = false;
    _phase = MainPhase.upload;

    notifyListeners();
  }

  /// 파운더가 볼 원시값 — 파일럿 중 로그 건전성 일일 확인용.
  DebugMetrics get debugMetrics => debugMetricsFrom(_storage.readEvents());

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

  /// 아직 3개를 못 채웠고 건너뛰지도 않았으면 첫 방문 상태다 — 업로드 존 자리에 온보딩 카드가 온다.
  ///
  /// 별도 화면이 아니라 메인의 한 상태이고, **거기서 3개를 다 채운다**(G1 #8 "0/3, 그 자리에서 완결").
  /// 첫 1개에서 카드를 치우면 카운터가 0/3에서 영원히 멈추고 "그 자리에서 완결"이 성립하지 않는다.
  bool get showsOnboarding =>
      !_onboardingSkipped && _storage.readRecipes().length < trustedRecipeGoal;
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

  /// 지금 날고 있는 매칭의 세대 — 돌아온 응답이 자기 세대가 아니면 조용히 버린다.
  /// 인식(_recognizeGeneration)과 같은 장치다.
  int _matchGeneration = 0;

  /// 확정 재료를 레시피 북과 맞춰 "오늘 할 3개"를 얻는다 — 코어 루프의 심장(#18).
  Future<void> requestSuggestions() async {
    final ingredients = [for (final i in matchableIngredients) i.name];
    if (ingredients.isEmpty) return;
    final generation = ++_matchGeneration;
    final epoch = _recordEpoch;

    // 이미 제안이 있는데 다시 부르는 건 "다시 제안"이다 — 낡은 걸 갱신하는 행위(ADR-0001).
    if (_suggestions.isNotEmpty) {
      await _appendUnlessReset(
        epoch,
        AppEvent.rematch(at: _now(), previousCount: _suggestions.length),
      );
    }

    final recipes = _storage.readRecipes();
    _phase = MainPhase.matching;
    _failure = null;
    // 지연은 호출별 지역 변수로 잰다 — 필드에 두면 겹친 호출이 덮어써 앞선 응답의 지연이 틀어진다.
    final startedAt = _now();
    notifyListeners();

    try {
      final result = await _gateway.match(
        ingredients: ingredients,
        recipes: recipes,
      );
      // 부족 4개 이상 제외와 3개 상한은 클라이언트가 한다 — 제외 수를 집계해야 하므로.
      final selection = selectSuggestions(result.suggestions);

      // 대체된 호출도 Gemini까지 갔고 토큰을 썼다 — 원가 원장은 호출마다 남긴다(스펙 US 28:
      // "LLM 호출마다 토큰 수와 추정 원가가 이벤트에 부착"). 세대 가드는 화면과 노출만 막는다.
      // 기록 초기화만 예외로 이 append를 건너뛴다(_recordEpoch 참조).
      await _appendUnlessReset(
        epoch,
        AppEvent.matchingDone(
          at: _now(),
          latency: _now().difference(startedAt),
          usage: result.usage,
          shownCount: selection.shown.length,
          excludedCount: selection.excludedCount,
        ),
      );

      // "다시 제안"이 겹쳐 새 호출이 떴다면 이 응답은 남의 화면이다 — 인식과 같은 세대 가드.
      if (generation != _matchGeneration) return;

      // 날아가는 동안 재료를 손댔다면, 이 제안은 뜨는 순간부터 낡은 재고의 답이다(ADR-0001).
      _stale = !listEquals(ingredients, [
        for (final i in matchableIngredients) i.name,
      ]);

      await _appendUnlessReset(
        epoch,
        AppEvent.suggestionsShown(
          at: _now(),
          suggestions: selection.shown,
          stale: _stale,
        ),
      );

      _suggestions = selection.shown;
      _excludedCount = selection.excludedCount;
      // 제안이 뜨면 체크리스트는 요약 한 줄로 접힌다(G1 #8).
      _checklistExpanded = false;
      _phase = MainPhase.suggestions;
    } on LlmFailure catch (e) {
      // 대체된 호출의 뒤늦은 실패 카드가 살아 있는 매칭을 덮지 않는다.
      if (generation != _matchGeneration) return;
      await _appendUnlessReset(
        epoch,
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
  ///
  /// 같은 제안의 실행취소 창이 살아 있는 동안의 재탭은 무시한다(false 반환) — 빠른 더블탭이
  /// cooked를 이중으로 남겨 성공 지표 2를 부풀리는 것을 막는다. 실행취소로 되돌린 뒤의
  /// 재탭은 새 기록이다 — 마음이 바뀐 건 실수가 아니다.
  Future<bool> markCooked(Suggestion suggestion) async {
    if (_pendingCooked == suggestion) return false;
    _pendingCooked = suggestion;
    notifyListeners();
    await _storage.appendEvent(
      AppEvent.cooked(at: _now(), suggestion: suggestion, stale: _stale),
    );
    return true;
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

  /// 이 제안의 실행취소 창이 닫혔다 — 그 사이 다른 제안의 "이거 했어요"가 pending을 바꿔
  /// 이 창을 밀어냈다면 pending은 그 새 제안의 것이므로 건드리지 않는다. 제안 대조로 판정하니
  /// 스낵바 hide 출처(레시피 북의 clearSnackBars 포함)와 무관하게 성립한다.
  void dismissUndoFor(Suggestion suggestion) {
    if (_pendingCooked != suggestion) return;
    _pendingCooked = null;
    notifyListeners();
  }

  /// "다른 사진으로 다시" — 코어 루프를 업로드부터 다시 시작한다(매일 찍는 2주 파일럿).
  ///
  /// 이벤트는 남기지 않는다 — 진짜 photoUpload는 다음 사진을 고르는 순간 찍힌다(측정 순도).
  /// 세션은 비워서 저장한다 — 안 비우면 브라우저를 닫았다 열 때 옛 체크리스트가 되살아난다.
  Future<void> startNewPhoto() async {
    // 날고 있는 인식·매칭 응답을 버린다 — 뒤늦게 돌아와 업로드 화면을 덮지 않게.
    _abandonInFlightRecognition();
    _matchGeneration++;
    _ingredients = [];
    _photo = null;
    _lastResizedPhoto = null;
    _suggestions = [];
    _excludedCount = 0;
    _stale = false;
    _checklistExpanded = true;
    _pendingCooked = null;
    _failure = null;
    _phase = MainPhase.upload;
    notifyListeners();
    await _saveSession();
  }

  /// 매칭 로딩 문구에 쓰는 수 — "레시피 북 N개와 맞춰보는 중".
  int get matchingRecipeCount => _storage.readRecipes().length;

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
    final epoch = _recordEpoch;
    final resized = await resizeForRecognition(original);
    _photo = resized.bytes;
    _lastResizedPhoto = resized.bytes;
    await _appendUnlessReset(
      epoch,
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

  /// 실패 인라인 카드의 "직접 입력으로 계속", 그리고 로딩 10초 후의 "취소".
  ///
  /// 빈 체크리스트 폴백이다(G1 #8, 막다른 화면 없음). 인식이 아직 날고 있을 수 있으므로
  /// 그 호출을 버린다 — 안 버리면 사용자가 직접 넣은 재료를 나중에 덮어쓰고,
  /// 실패하면 이미 넘어간 사람에게 에러 카드를 띄운다.
  Future<void> continueWithEmptyChecklist() async {
    _abandonInFlightRecognition();
    _ingredients = [];
    _photo = null;
    _failure = null;
    _phase = MainPhase.checklist;
    notifyListeners();
    await _saveSession();
  }

  /// 기록 구간의 세대(#144). [resetPilotRecord]가 올린다.
  ///
  /// 원가 원장은 **버려진 호출도** 기록하는 게 원칙이다(스펙 US 28) — 취소하든 재업로드하든
  /// Gemini까지 갔고 토큰을 썼기 때문이다. 그래서 `appendEvent`는 세대 가드보다 **앞에** 있다.
  ///
  /// 초기화만 예외다. 초기화는 그 호출이 속한 **구간 자체를 지운다** — 이미 지워진 구간의
  /// 이벤트가 응답 지연으로 뒤늦게 되살아나면 파운더가 푸터에서 보는 수는 "이벤트 1"이 되고,
  /// AC("초기화 후 정상 상태 = 이벤트 0")가 깨진다. 실 인식이 5~10초라 창이 좁지도 않다.
  /// 손실이 아니다 — 그 이벤트는 초기화가 어차피 지웠을 구간의 것이다.
  int _recordEpoch = 0;

  /// 시작할 때의 구간이 아직 살아 있을 때만 기록한다 — 초기화된 구간의 이벤트는 버린다.
  Future<void> _appendUnlessReset(int epoch, AppEvent event) async {
    if (epoch != _recordEpoch) return;
    await _storage.appendEvent(event);
  }

  /// 지금 날고 있는 인식 호출을 버린다 — 취소·이탈에 쓴다.
  ///
  /// Future 자체는 못 끊는다(HTTP는 서버까지 갔다). 대신 세대 번호를 올려, 돌아온 응답이
  /// 자기 세대가 아니면 조용히 버리게 한다.
  void _abandonInFlightRecognition() => _recognizeGeneration++;
  int _recognizeGeneration = 0;

  Future<void> _recognize(Uint8List jpegBytes) async {
    final generation = ++_recognizeGeneration;
    final epoch = _recordEpoch;
    _phase = MainPhase.recognizing;
    _failure = null;
    // 지연은 호출별 지역 변수로 잰다 — 필드에 두면 겹친 호출이 덮어써 앞선 응답의 지연이 틀어진다.
    // 필드는 로딩 문구가 경과를 재는 데 계속 쓰이므로 같은 시각으로 함께 남긴다.
    final startedAt = _now();
    _recognizeStartedAt = startedAt;
    notifyListeners();

    try {
      final result = await _gateway.recognize(jpegBytes);
      // 버려진 호출도 Gemini까지 갔고 토큰을 썼다 — 원가 원장은 호출마다 남긴다(스펙 US 28:
      // "LLM 호출마다 토큰 수와 추정 원가가 이벤트에 부착"). 세대 가드는 화면만 막는다.
      // 기록 초기화만 예외로 이 append를 건너뛴다(_recordEpoch 참조).
      await _appendUnlessReset(
        epoch,
        AppEvent.recognitionDone(
          at: _now(),
          latency: _now().difference(startedAt),
          usage: result.usage,
          count: result.ingredients.length,
        ),
      );

      // 사용자가 기다리다 취소하고 직접 입력으로 넘어갔다면, 이 응답은 남의 화면이다.
      if (generation != _recognizeGeneration) return;

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
      // 취소하고 넘어간 사용자에게 뒤늦은 에러 카드를 띄우지 않는다.
      if (generation != _recognizeGeneration) return;
      await _appendUnlessReset(
        epoch,
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
