// 레시피 북의 상태 — URL 저장·삭제와 제목 기반 재료 추출(#17). 서버 모드는 서버 CRUD를 미러링한다(#121).
import 'package:flutter/foundation.dart';

import '../data/server_recipe_repository.dart';
import '../data/storage.dart';
import '../domain/app_event.dart';
import '../domain/recipe.dart';
import '../llm/llm_gateway.dart';

/// 파일럿이 목표로 하는 저장 레시피 수 — 온보딩 카드의 0/3과 넛지 칩의 기준(G1 #8).
const trustedRecipeGoal = 3;

/// 서버 미러의 동기 상태 — 로컬 모드는 항상 [ready]다(#121).
enum RecipeSyncState { loading, error, ready }

/// 저장 요청이 어떻게 끝났는지 — 폼이 그 자리에서 사용자에게 말할 수 있게 한다(#127).
///
/// **[accepted]는 "폼이 더 말할 것이 없다"는 뜻이지 저장 성공이 아니다.** 서버 모드의 저장
/// 실패도 여기로 온다 — 그건 `addFailure` → `RecipeAddFailureCard`가 말하고, 폼이 겹쳐 말하면
/// 같은 사건을 두 번 말하게 된다. 나머지 셋은 서버·LLM 호출에 닿기도 전에 걸러진 거절이고,
/// 예전에는 전부 조용한 return이라 사용자가 "왜 안 담기지"에 갇혔다.
enum RecipeAddOutcome {
  /// 저장 경로에 들어갔다 — 결과는 기존 표면이 말한다.
  accepted,

  /// 같은 URL이 이미 레시피 북에 있다 — URL이 식별자다.
  duplicateUrl,

  /// URL 또는 제목이 비었다.
  incomplete,

  /// 이미 저장이 도는 중이다(더블탭).
  busy,
}

class RecipeBookController extends ChangeNotifier {
  /// [server]가 null이면 로컬 모드(현행 그대로), 주어지면 서버 모드다(#121).
  ///
  /// 서버 모드의 미러 계약 — 서버가 진실원이고 storage의 레시피는 동기 read seam을 지키는
  /// 렌더 버퍼다(캐시 승격이 아니다). recipes getter·메인의 동기 read·backup export가 전부
  /// 이 미러를 읽으므로, 미러 반영은 **반드시 서버 응답을 확인한 뒤에만** 한다(낙관적 갱신 금지).
  RecipeBookController(
    this._gateway,
    this._storage, {
    DateTime Function()? now,
    // 외부 파라미터명은 server다 — Dart 3.12 private named parameter 관용구(ApiV1LlmGateway와 동일).
    this._server,
  }) : _now = now ?? DateTime.now;

  final LlmGateway _gateway;
  final Storage _storage;
  final DateTime Function() _now;
  final ServerRecipeRepository? _server;

  List<Recipe> get recipes => _storage.readRecipes();

  /// 저장 중인가 — 추출 호출이 도는 동안 참이다.
  bool get saving => _saving;
  bool _saving = false;

  /// 마지막 저장 실패. 추출이 죽어도 레시피는 저장되므로, 이건 재료가 비었다는 신호에 가깝다.
  LlmFailureKind? get failure => _failure;
  LlmFailureKind? _failure;

  /// 서버 미러의 동기 상태 — 서버 모드는 [hydrate]가 전이시키고, 로컬 모드는 항상 ready다.
  RecipeSyncState get syncState =>
      _server == null ? RecipeSyncState.ready : _syncState;
  RecipeSyncState _syncState = RecipeSyncState.loading;

  /// 마지막 하이드레이트 실패 — 리스트 자리 에러 카드가 문구를 고르는 근거.
  RecipeApiFailureKind? get syncFailure => _syncFailure;
  RecipeApiFailureKind? _syncFailure;

  /// 마지막 저장(add) 실패 — 서버 모드는 추출 실패(502)=미저장이 서버 정책이라 실패 카드가 뜬다.
  RecipeApiFailureKind? get addFailure => _addFailure;
  RecipeApiFailureKind? _addFailure;

  /// 실패한 저장의 입력 — RecipeForm이 submit 시 필드를 비우므로 재시도용으로 여기 보관한다.
  ({String url, String title})? get failedAdd => _failedAdd;
  ({String url, String title})? _failedAdd;

  /// 실패 카드의 "닫기" — 재시도를 포기하고 카드를 접는다.
  void clearAddFailure() {
    _addFailure = null;
    _failedAdd = null;
    notifyListeners();
  }

  /// 서버 목록을 미러로 당긴다 — 부르는 곳은 엔트리 부팅 1회 + 에러 카드 재시도뿐이다.
  ///
  /// 변경(add·재추출·삭제) 후에는 다시 부르지 않는다 — 각 변경이 서버 응답으로 미러를 갱신한다.
  Future<void> hydrate() async {
    final server = _server;
    if (server == null) return;

    _syncState = RecipeSyncState.loading;
    _syncFailure = null;
    notifyListeners();

    try {
      final fetched = await server.fetchAll();
      // 하이드레이트 가드(#165) — 빈 서버 목록은 비어 있지 않은 미러를 덮지 않는다.
      // 1계정 1기기 전제에서 이 조합은 "아직 이전 안 됨"만 의미할 수 있어 위양성이 구조적으로 없다
      // (다른 기기가 같은 계정의 서버 북을 비울 길이 없다). 401 재등록도 같은 자리로 들어온다 —
      // 새 빈 계정으로 하이드레이트하는데 미러를 지키는 게 이 가드다.
      //
      // 범위는 미러 보존 + 이벤트 1건까지다. UI 안내는 만들지 않는다(안내는 런북이 한다).
      // 상태는 반드시 ready다 — error로 두면 폼 잠금·서버 저장 게이트·가져오기 게이트가 전부 닫혀
      // 이전 경로(가져오기 → bulk)까지 함께 막힌다.
      if (fetched.isEmpty && recipes.isNotEmpty) {
        await _storage.appendEvent(
          AppEvent.errorShown(
            at: _now(),
            kind: 'emptyServerBook',
            stage: 'hydrate',
          ),
        );
      } else {
        await _storage.writeRecipes(fetched);
      }
      _syncState = RecipeSyncState.ready;
    } on RecipeApiFailure catch (e) {
      _syncState = RecipeSyncState.error;
      _syncFailure = e.kind;
    }
    notifyListeners();
  }

  /// URL 하나를 저장한다. 제목은 사용자가 적고, 재료는 그 제목에서 추론한다.
  ///
  /// 추출이 실패해도 레시피 자체는 저장한다 — 재료 없는 레시피가 없는 레시피보다 낫고,
  /// vision-tech 리서치가 예고한 "추출 실패 시 수동 입력 폴백"의 자리이기도 하다.
  /// 서버 모드는 반대로 추출 실패=미저장이 서버 정책이다 — [_addToServer] 참조.
  ///
  /// 반환값은 [RecipeAddOutcome]이다 — 거절 세 갈래를 **폼이 그 자리에서 말할 수 있게**(#127).
  /// 셋 다 첫 await 전에 결정되므로 거절은 마이크로태스크 안에서 돌아온다(프레임 전이다).
  Future<RecipeAddOutcome> add({
    required String url,
    required String title,
  }) async {
    // 더블탭 가드 — 첫 탭의 await 중 둘째 탭이 옛 목록으로 dedup을 통과해 추출·저장이
    // 2회 돌던 결함의 수리다. _saving은 로컬(아래)·서버([_addToServer]) 모두 첫 await 전에
    // 동기로 세팅되므로 최상단 동기 가드가 양 모드에서 성립한다.
    if (_saving) return RecipeAddOutcome.busy;
    final trimmedUrl = url.trim();
    final trimmedTitle = title.trim();
    if (trimmedUrl.isEmpty || trimmedTitle.isEmpty) {
      return RecipeAddOutcome.incomplete;
    }

    // URL이 식별자다 — 같은 레시피를 두 번 담지 않는다.
    if (recipes.any((r) => r.url == trimmedUrl)) {
      return RecipeAddOutcome.duplicateUrl;
    }

    if (_server != null) {
      await _addToServer(_server, url: trimmedUrl, title: trimmedTitle);
      return RecipeAddOutcome.accepted;
    }

    _saving = true;
    _failure = null;
    notifyListeners();

    var ingredients = const <String>[];
    LlmUsage? usage;
    try {
      final result = await _gateway.extractIngredients(trimmedTitle);
      ingredients = result.ingredients;
      usage = result.usage;
    } on LlmFailure catch (e) {
      _failure = e.kind;
      await _storage.appendEvent(
        AppEvent.errorShown(at: _now(), kind: e.kind.name, stage: 'extraction'),
      );
    }

    final recipe = Recipe(
      url: trimmedUrl,
      title: trimmedTitle,
      ingredients: ingredients,
    );
    await _storage.writeRecipes([...recipes, recipe]);
    await _storage.appendEvent(
      AppEvent.recipeBookChanged(
        at: _now(),
        action: RecipeBookAction.add,
        url: trimmedUrl,
        title: trimmedTitle,
        ingredientCount: ingredients.length,
        usage: usage,
      ),
    );

    _saving = false;
    notifyListeners();
    return RecipeAddOutcome.accepted;
  }

  /// 서버 모드 저장 — 추출은 서버가 저장 시 1회 수행하고, 실패(502)면 저장되지 않는다.
  Future<void> _addToServer(
    ServerRecipeRepository server, {
    required String url,
    required String title,
  }) async {
    // 하이드레이트가 안 끝났거나 실패한 상태면 저장하지 않는다 — 미러가 정확하지 않아
    // dedup 가드가 성립하지 않고, 에러 상태 위에 저장을 겹치면 상태가 꼬인다.
    // 무음 폐기는 금지다 — 기존 실패 카드로 표면화해 재시도 길을 연다. 이 분기에선 폼이
    // 잠겨 있어(enabled = syncState == ready) 실패 카드의 "다시 시도"가 유일한 길이고,
    // 그래서 [failedAdd]가 그 입력을 쥐고 있어야 한다.
    // 서버 호출 자체가 없었으므로 이벤트는 남기지 않는다.
    if (syncState != RecipeSyncState.ready) {
      _addFailure = _syncFailure ?? RecipeApiFailureKind.unavailable;
      _failedAdd = (url: url, title: title);
      notifyListeners();
      return;
    }

    _saving = true;
    _addFailure = null;
    _failedAdd = null;
    notifyListeners();

    try {
      final created = await server.create(url: url, title: title);
      await _storage.writeRecipes([...recipes, created]);
      // usage 인자 생략 — 추출은 서버 안에서 돌고 응답에 usage가 없다.
      await _storage.appendEvent(
        AppEvent.recipeBookChanged(
          at: _now(),
          action: RecipeBookAction.add,
          url: url,
          title: title,
          ingredientCount: created.ingredients.length,
        ),
      );
    } on RecipeApiFailure catch (e) {
      // 미저장이므로 미러도 무변화 — 실패 카드가 재시도를 연다.
      _addFailure = e.kind;
      _failedAdd = (url: url, title: title);
      await _storage.appendEvent(
        AppEvent.errorShown(at: _now(), kind: e.kind.name, stage: 'extraction'),
      );
    }

    _saving = false;
    notifyListeners();
  }

  /// 추출만 다시 돌린다 — 레시피는 이미 저장돼 있고 재료만 비어 있다(#34, 스펙 US 22 인라인 원칙).
  ///
  /// 재료 0개 레시피는 영원히 매칭되지 않으므로, 사용자가 그 자리에서 복구할 길이 있어야 한다.
  /// 없으면 질문 2가 망가진 레시피 북 위에서 측정된다.
  Future<void> retryExtraction(String url) async {
    final target = recipes.where((r) => r.url == url).firstOrNull;
    if (target == null || _retryingUrl != null) return;

    // 서버에 있는 항목만 서버 분기로 간다. 하이드레이트 가드(#165)가 지킨 미이전 항목은
    // 서버에 없어 PATCH할 곳이 없으므로 아래 로컬 경로가 맡는다 — 미러가 그 항목의 유일한 집이고,
    // 고친 재료는 이전(bulk) 때 그대로 서버로 실려간다. 여기서 막으면 "다시 시도"가 죽은 버튼이 된다.
    if (_server != null && target.id != null) {
      await _retryExtractionOnServer(_server, target);
      return;
    }

    _retryingUrl = url;
    _failure = null;
    notifyListeners();

    try {
      // url도 넘긴다 — 서버 경계는 URL 내용 기반 추출 사다리를 탄다(#123, 프록시는 무시).
      final result = await _gateway.extractIngredients(
        target.title,
        url: target.url,
      );
      await _storage.writeRecipes([
        for (final r in recipes)
          if (r.url == url)
            Recipe(url: r.url, title: r.title, ingredients: result.ingredients)
          else
            r,
      ]);
      // 재추출도 LLM 호출이다 — 원가는 호출마다 남긴다(스펙 US 28).
      await _storage.appendEvent(
        AppEvent.recipeBookChanged(
          at: _now(),
          action: RecipeBookAction.reextract,
          url: url,
          title: target.title,
          ingredientCount: result.ingredients.length,
          usage: result.usage,
        ),
      );
    } on LlmFailure catch (e) {
      _failure = e.kind;
      await _storage.appendEvent(
        AppEvent.errorShown(at: _now(), kind: e.kind.name, stage: 'extraction'),
      );
    }

    _retryingUrl = null;
    notifyListeners();
  }

  /// 서버 모드 재추출 — 추출은 LLM seam으로 직접 돌리고(usage가 여기서 나온다),
  /// 결과를 PATCH로 서버에 실은 뒤 **그 응답으로** 미러의 해당 항목을 교체한다.
  Future<void> _retryExtractionOnServer(
    ServerRecipeRepository server,
    Recipe target,
  ) async {
    // id 없는 항목은 [retryExtraction]이 로컬 경로로 보낸다(#165) — 여기 오면 계약 위반이다.
    final id = target.id;
    if (id == null) return;

    _retryingUrl = target.url;
    _failure = null;
    notifyListeners();

    // try 밖에 둔다 — 이 메서드엔 throw 지점이 둘이고, 뒤쪽(PATCH)에서 죽으면 앞쪽 LLM 호출은
    // 이미 성공해 토큰이 결제된 뒤다. try 안의 지역 변수로 두면 catch에서 스코프 밖이라
    // 그 원가가 원장에 못 들어간다(#127). add()가 같은 이유로 쓰는 관용구다.
    LlmUsage? usage;
    try {
      // url도 넘긴다 — 서버 경계는 URL 내용 기반 추출 사다리를 탄다(#123).
      final result = await _gateway.extractIngredients(
        target.title,
        url: target.url,
      );
      usage = result.usage;
      final updated = await server.patchIngredients(
        id: id,
        ingredients: result.ingredients,
      );
      await _storage.writeRecipes([
        for (final r in recipes)
          if (r.url == target.url) updated else r,
      ]);
      // 재추출도 LLM 호출이다 — 원가는 호출마다 남긴다(스펙 US 28).
      await _storage.appendEvent(
        AppEvent.recipeBookChanged(
          at: _now(),
          action: RecipeBookAction.reextract,
          url: target.url,
          title: target.title,
          ingredientCount: updated.ingredients.length,
          usage: usage,
        ),
      );
    } on LlmFailure catch (e) {
      // 추출 자체가 죽었다 — 결제된 원가가 없으므로 usage도 없다(여기선 항상 null이다).
      _failure = e.kind;
      await _storage.appendEvent(
        AppEvent.errorShown(at: _now(), kind: e.kind.name, stage: 'extraction'),
      );
    } on RecipeApiFailure catch (e) {
      // PATCH가 죽었다 — 서버가 진실원이므로 미러도 갱신하지 않는다. 단 **LLM은 이미 돌았다** —
      // 실패 지점은 추출이 아니라 저장이고(stage), 결제된 토큰은 저장 실패와 무관하게 원장에
      // 남아야 한다(usage). 둘 다 빠뜨리면 재추출 원가가 P2 산식에서 샌다(#127, 스펙 US 28).
      await _storage.appendEvent(
        AppEvent.errorShown(
          at: _now(),
          kind: e.kind.name,
          stage: 'reextractSave',
          usage: usage,
        ),
      );
    }

    _retryingUrl = null;
    notifyListeners();
  }

  /// 지금 재추출 중인 레시피의 URL — 타일이 자기 자리에서만 진행 표시를 한다.
  String? get retryingUrl => _retryingUrl;
  String? _retryingUrl;

  /// 삭제 직후 실행취소 창이 열려 있는 항목 — 로컬 모드에서만 채워진다.
  ///
  /// 서버 모드의 undo는 재-POST가 서버 재추출(LLM 원가)을 다시 돌려야 해 범위 밖이다(#121).
  ({Recipe recipe, int index})? get pendingRemove => _pendingRemove;
  ({Recipe recipe, int index})? _pendingRemove;

  /// 마지막 서버 삭제 실패(비-404) — 타일은 남고(미러 유지), 페이지가 스낵바로 표면화한다.
  RecipeApiFailureKind? get removeFailure => _removeFailure;
  RecipeApiFailureKind? _removeFailure;

  Future<void> remove(String url) async {
    final before = recipes;
    final index = before.indexWhere((r) => r.url == url);
    if (index < 0) return;
    final target = before[index];

    _removeFailure = null;

    // 서버 미반영 항목(id 없음)은 DELETE할 곳이 없다 — 하이드레이트 가드(#165)가 지킨 미이전
    // 항목이 여기 해당한다. 404를 성공으로 보는 것과 같은 판정이다: 삭제의 목표 상태(서버에 없음)가
    // 이미 참이므로 미러에서만 지운다. 여기서 return하면 X를 눌러도 아무 일이 없는 죽은 버튼이 된다.
    final id = target.id;
    if (_server != null && id != null) {
      try {
        await _server.delete(id);
      } on RecipeApiFailure catch (e) {
        // 부재(404)는 성공 취급 — 삭제의 목표 상태(없음)가 이미 이루어져 있다.
        if (e.kind != RecipeApiFailureKind.notFound) {
          // 서버에 남은 걸 화면에서만 지우면 다음 하이드레이트에 되살아난다 — 미러 유지,
          // 실패 이유는 removeFailure로 표면화한다(무표면이면 X를 눌러도 타일만 남는다).
          _removeFailure = e.kind;
          await _storage.appendEvent(
            AppEvent.errorShown(at: _now(), kind: e.kind.name, stage: 'remove'),
          );
          notifyListeners();
          return;
        }
      }
    }

    await _storage.writeRecipes([
      for (final r in recipes)
        if (r.url != url) r,
    ]);
    await _storage.appendEvent(
      AppEvent.recipeBookChanged(
        at: _now(),
        action: RecipeBookAction.remove,
        url: url,
        title: target.title,
        ingredientCount: target.ingredients.length,
      ),
    );
    if (_server == null) {
      // 파괴적 삭제에 5초 실행취소를 연다 — LLM 추출 원가가 든 자산이라 실수 한 번에 잃지
      // 않게(cooked의 markCooked/undoCooked와 같은 문법, G1 #8).
      _pendingRemove = (recipe: target, index: index);
    }
    notifyListeners();
  }

  /// 5초 안에 되돌렸다 — 지운 레시피를 원위치에 복원한다(로컬 모드 전용).
  Future<void> undoRemove() async {
    final pending = _pendingRemove;
    if (pending == null) return;
    _pendingRemove = null;
    final list = [...recipes];
    // 실행취소 창이 열린 사이 같은 URL이 다시 저장됐다면 복제하지 않는다 — URL이 식별자다.
    if (list.any((r) => r.url == pending.recipe.url)) {
      notifyListeners();
      return;
    }
    list.insert(pending.index.clamp(0, list.length), pending.recipe);
    await _storage.writeRecipes(list);
    // 취소도 이벤트다 — remove만 확정 기록으로 남으면 분석의 레시피 북 이력이 실제 북과
    // 어긋난다(cooked/cookedUndo 짝과 동형). 복원은 재추출·원가가 없어 usage를 남기지 않는다.
    await _storage.appendEvent(
      AppEvent.recipeBookChanged(
        at: _now(),
        action: RecipeBookAction.restore,
        url: pending.recipe.url,
        title: pending.recipe.title,
        ingredientCount: pending.recipe.ingredients.length,
      ),
    );
    notifyListeners();
  }

  /// 실행취소 창이 닫혔다 — 되돌릴 수 없다(cooked의 dismissUndo와 같은 문법).
  void dismissRemoveUndo() {
    if (_pendingRemove == null) return;
    _pendingRemove = null;
    notifyListeners();
  }

  /// 이 레시피의 실행취소 창이 닫혔다 — 그 사이 다른 삭제가 pending을 바꿨다면 건드리지 않는다.
  /// URL 대조로 판정하니 스낵바 hide 출처(다른 화면의 clearSnackBars 포함)와 무관하게 성립한다.
  void dismissRemoveUndoFor(Recipe recipe) {
    if (_pendingRemove?.recipe.url != recipe.url) return;
    _pendingRemove = null;
    notifyListeners();
  }
}
