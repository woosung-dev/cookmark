// 컷오버 엔트리 — COOKMARK_API_BASE가 있으면 apps/api FastAPI, 없으면 main.dart와 동일한 프록시 조립.
//
// 실행 (컷오버 빌드).
//   flutter build web -t lib/main_api_cutover.dart \
//     --dart-define=COOKMARK_API_BASE=http://localhost:8099 \
//     --dart-define=COOKMARK_SESSION_TOKEN=<scripts/seed_sessions.py 토큰>
// dart-define 없이 빌드하면 ProxyLlmGateway 폴백 = 파일럿 빌드와 동일 동작이다.
// 토큰이 비어도 부팅은 한다 — 401이 화면 인라인 실패로 가시화되는 편이 조용한 중단보다 낫다.
// 스파이크 자동발화(_spike_photo)는 싣지 않는다 — 여긴 사용자 조작으로만 관통한다.
import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'data/server_recipe_repository.dart';
import 'data/storage.dart';
import 'llm/api_v1_llm_gateway.dart';
import 'llm/llm_gateway.dart';
import 'llm/proxy_llm_gateway.dart';
import 'ui/backup_controller.dart';
import 'ui/main_controller.dart';
import 'ui/recipe_book_controller.dart';

const _base = String.fromEnvironment('COOKMARK_API_BASE');
const _token = String.fromEnvironment('COOKMARK_SESSION_TOKEN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await Storage.open();
  final LlmGateway gateway = _base.isEmpty
      ? ProxyLlmGateway()
      : ApiV1LlmGateway(baseUrl: _base, sessionToken: _token);
  final server = _base.isEmpty
      ? null
      : ServerRecipeRepository(baseUrl: _base, sessionToken: _token);
  final controller = MainController(gateway, storage)
    // 냉장고 앞에서 브라우저를 닫았다 열어도 하던 데서 이어간다(#15).
    ..restoreSession();
  final recipeBookController = RecipeBookController(
    gateway,
    storage,
    server: server,
  );
  // 서버 모드면 부팅 시 서버 목록을 로컬 미러로 당긴다 — 부팅을 막지 않고,
  // 실패는 레시피 북의 인라인 에러 카드로 가시화된다(#121).
  if (server != null) unawaited(recipeBookController.hydrate());
  runApp(
    CookmarkApp(
      controller: controller,
      recipeBookController: recipeBookController,
      backupController: BackupController(
        storage,
        server: server,
        // 미러가 ready가 아닌 동안 가져오기를 막는다 — 스테일 dedup 중복 등록 방지(#121).
        serverSyncState: () => recipeBookController.syncState,
        // 가져오기 확정 후 재수화도 같은 hydrate로 — 실패 시 error 전이로 게이트가 닫힌다.
        serverRehydrate: recipeBookController.hydrate,
      ),
    ),
  );
}
