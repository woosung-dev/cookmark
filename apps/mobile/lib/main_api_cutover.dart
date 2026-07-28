// 컷오버 엔트리 — COOKMARK_SERVER_BASE가 있으면 apps/api FastAPI, 없으면 main.dart와 동일한 프록시 조립.
//
// 실행 (컷오버 빌드).
//   flutter build web -t lib/main_api_cutover.dart \
//     --dart-define=COOKMARK_SERVER_BASE=http://localhost:8099 \
//     --dart-define=COOKMARK_REGISTER_KEY=<서버의 COOKMARK_REGISTER_KEY와 같은 값>
// dart-define 없이 빌드하면 ProxyLlmGateway 폴백 = 파일럿 빌드와 동일 동작이다.
// 이름은 백엔드마다 갈려 있다 — 폴백이 타는 프록시 주소는 COOKMARK_API_BASE다(#164).
// 세션 토큰을 빌드에 박던 시절(COOKMARK_SESSION_TOKEN·1빌드=1계정)은 끝났다 — 앱이 부팅 경로에서
// 스스로 등록한다(#168 · ADR-0012). 등록 키가 비거나 틀리면 서버가 403을 내고, 그건 재시도로
// 고쳐지지 않아 인라인 실패 카드로 뜬다 — 조용한 중단보다 낫다는 판단은 그대로다.
// 스파이크 자동발화(_spike_photo)는 싣지 않는다 — 여긴 사용자 조작으로만 관통한다.
import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'auth/api_v1_device_session.dart';
import 'data/server_recipe_repository.dart';
import 'data/storage.dart';
import 'llm/api_v1_llm_gateway.dart';
import 'llm/llm_gateway.dart';
import 'llm/proxy_llm_gateway.dart';
import 'ui/backup_controller.dart';
import 'ui/main_controller.dart';
import 'ui/recipe_book_controller.dart';

const _serverBase = String.fromEnvironment('COOKMARK_SERVER_BASE');
const _registerKey = String.fromEnvironment('COOKMARK_REGISTER_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await Storage.open();
  // 기기 세션 경계 — 저장된 토큰이 없으면 첫 인증 요청이 등록을 발화시킨다(#168).
  // **runApp 앞에서 await하지 않는다**: 등록은 부팅을 막지 않고, 로그인 화면도 만들지 않는다.
  final session = _serverBase.isEmpty
      ? null
      : ApiV1DeviceSession(
          baseUrl: _serverBase,
          registerKey: _registerKey,
          storage: storage,
        );
  final LlmGateway gateway = session == null
      ? ProxyLlmGateway()
      : ApiV1LlmGateway(baseUrl: _serverBase, session: session);
  final server = session == null
      ? null
      : ServerRecipeRepository(baseUrl: _serverBase, session: session);
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
