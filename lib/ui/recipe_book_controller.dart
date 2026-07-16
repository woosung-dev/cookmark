// 레시피 북의 상태 — URL 저장·삭제와 제목 기반 재료 추출(#17).
import 'package:flutter/foundation.dart';

import '../data/storage.dart';
import '../domain/app_event.dart';
import '../domain/recipe.dart';
import '../llm/llm_gateway.dart';

/// 파일럿이 목표로 하는 저장 레시피 수 — 온보딩 카드의 0/3과 넛지 칩의 기준(G1 #8).
const trustedRecipeGoal = 3;

class RecipeBookController extends ChangeNotifier {
  RecipeBookController(this._gateway, this._storage, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final LlmGateway _gateway;
  final Storage _storage;
  final DateTime Function() _now;

  List<Recipe> get recipes => _storage.readRecipes();

  /// 저장 중인가 — 추출 호출이 도는 동안 참이다.
  bool get saving => _saving;
  bool _saving = false;

  /// 마지막 저장 실패. 추출이 죽어도 레시피는 저장되므로, 이건 재료가 비었다는 신호에 가깝다.
  LlmFailureKind? get failure => _failure;
  LlmFailureKind? _failure;

  /// URL 하나를 저장한다. 제목은 사용자가 적고, 재료는 그 제목에서 추론한다.
  ///
  /// 추출이 실패해도 레시피 자체는 저장한다 — 재료 없는 레시피가 없는 레시피보다 낫고,
  /// vision-tech 리서치가 예고한 "추출 실패 시 수동 입력 폴백"의 자리이기도 하다.
  Future<void> add({required String url, required String title}) async {
    final trimmedUrl = url.trim();
    final trimmedTitle = title.trim();
    if (trimmedUrl.isEmpty || trimmedTitle.isEmpty) return;

    // URL이 식별자다 — 같은 레시피를 두 번 담지 않는다.
    if (recipes.any((r) => r.url == trimmedUrl)) return;

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
  }

  /// 추출만 다시 돌린다 — 레시피는 이미 저장돼 있고 재료만 비어 있다(#34, 스펙 US 22 인라인 원칙).
  ///
  /// 재료 0개 레시피는 영원히 매칭되지 않으므로, 사용자가 그 자리에서 복구할 길이 있어야 한다.
  /// 없으면 질문 2가 망가진 레시피 북 위에서 측정된다.
  Future<void> retryExtraction(String url) async {
    final target = recipes.where((r) => r.url == url).firstOrNull;
    if (target == null || _retryingUrl != null) return;

    _retryingUrl = url;
    _failure = null;
    notifyListeners();

    try {
      final result = await _gateway.extractIngredients(target.title);
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

  /// 지금 재추출 중인 레시피의 URL — 타일이 자기 자리에서만 진행 표시를 한다.
  String? get retryingUrl => _retryingUrl;
  String? _retryingUrl;

  Future<void> remove(String url) async {
    final target = recipes.where((r) => r.url == url).firstOrNull;
    if (target == null) return;

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
    notifyListeners();
  }
}
