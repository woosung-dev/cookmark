// 테스트용 결정적 서버 레시피 북 — 유닛·E2E가 ServerRecipeRepository 자리에 주입한다(#121).
import 'package:cookmark/data/server_recipe_repository.dart';
import 'package:cookmark/domain/recipe.dart';

/// 인메모리 서버 레시피 북. 지연·실패를 주입해 로딩·에러 경로를 테스트한다(FakeLlmGateway 관용구).
///
/// id는 'srv-1'부터 단조 증가 — 서버가 UUID를 발급하듯 여기서 발급하고, 들어온 id는 무시한다.
class FakeServerRecipeRepository implements ServerRecipeRepository {
  FakeServerRecipeRepository({
    List<Recipe> seed = const [],
    this.latency = Duration.zero,
    this.failure,
  }) {
    recipes.addAll(seed.map(_ensureId));
  }

  /// 서버에 저장된 항목 — 삽입순. 테스트가 직접 들여다보거나 조작해도 된다.
  final List<Recipe> recipes = [];

  /// 응답 전 대기 — 로딩 상태를 테스트하려면 여기를 늘린다.
  final Duration latency;

  /// null이 아니면 모든 호출이 이 실패로 끝난다.
  ///
  /// 가변인 이유 — "실패했다가 다시 시도하면 성공한다"를 한 테스트 안에서 재현하려면
  /// 도중에 꺼야 한다(FakeLlmGateway.failure와 같은 관용구).
  RecipeApiFailure? failure;

  /// 호출 기록 — "다시 시도"가 실제로 재호출하는지, 무엇을 보냈는지 검증할 때 쓴다.
  int fetchAllCallCount = 0;
  int createCallCount = 0;
  int patchCallCount = 0;
  int deleteCallCount = 0;
  int importBulkCallCount = 0;
  List<Recipe>? lastImportBulk;

  /// 서버 create가 저장 시 1회 추출하는 것을 흉내 낸다 — 제목 → 재료(FakeLlmGateway.extractions와 동일).
  final Map<String, List<String>> extractions = {
    '김치찌개': ['김치', '돼지고기', '두부', '대파', '고춧가루'],
    '애호박볶음': ['애호박', '대파', '소금', '식용유'],
    '계란찜': ['계란', '대파', '새우젓'],
  };

  static const _fallbackExtraction = ['소금', '식용유'];

  int _idSeq = 0;

  @override
  Future<List<Recipe>> fetchAll() async {
    fetchAllCallCount++;
    await _gate();
    return List.of(recipes);
  }

  @override
  Future<Recipe> create({required String url, required String title}) async {
    createCallCount++;
    await _gate();
    final recipe = Recipe(
      id: _newId(),
      url: url,
      title: title,
      ingredients: extractions[title] ?? _fallbackExtraction,
    );
    recipes.add(recipe);
    return recipe;
  }

  @override
  Future<Recipe> patchIngredients({
    required String id,
    required List<String> ingredients,
  }) async {
    patchCallCount++;
    await _gate();
    final index = recipes.indexWhere((r) => r.id == id);
    if (index < 0) throw const RecipeApiFailure(RecipeApiFailureKind.notFound);
    final updated = recipes[index].copyWith(ingredients: ingredients);
    recipes[index] = updated;
    return updated;
  }

  @override
  Future<void> delete(String id) async {
    deleteCallCount++;
    await _gate();
    final index = recipes.indexWhere((r) => r.id == id);
    if (index < 0) throw const RecipeApiFailure(RecipeApiFailureKind.notFound);
    recipes.removeAt(index);
  }

  @override
  Future<List<Recipe>> importBulk(List<Recipe> recipes) async {
    importBulkCallCount++;
    lastImportBulk = recipes;
    await _gate();
    // 서버가 id를 발급한다 — 들어온 id는 버리고 새로 단다(실서버 계약과 동일).
    final saved = [
      for (final r in recipes)
        Recipe(
          id: _newId(),
          url: r.url,
          title: r.title,
          ingredients: r.ingredients,
        ),
    ];
    this.recipes.addAll(saved);
    return saved;
  }

  Future<void> _gate() async {
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    final fail = failure;
    if (fail != null) throw fail;
  }

  String _newId() => 'srv-${++_idSeq}';

  Recipe _ensureId(Recipe r) => r.id != null
      ? r
      : Recipe(
          id: _newId(),
          url: r.url,
          title: r.title,
          ingredients: r.ingredients,
        );
}
