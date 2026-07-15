// 엔트리 — 운영 의존성(서버리스 프록시 경계·로컬 스토리지)을 조립해 앱에 넘긴다.
import 'package:flutter/material.dart';

import 'app.dart';
import 'data/storage.dart';
import 'llm/proxy_llm_gateway.dart';
import 'ui/main_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await Storage.open();
  final controller = MainController(ProxyLlmGateway(), storage)
    // 냉장고 앞에서 브라우저를 닫았다 열어도 하던 데서 이어간다(#15).
    ..restoreSession();
  runApp(CookmarkApp(controller: controller));
}
