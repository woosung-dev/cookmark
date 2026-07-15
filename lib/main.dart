// 엔트리 — 운영 의존성(서버리스 프록시 경계·로컬 스토리지)을 조립해 앱에 넘긴다.
import 'package:flutter/material.dart';

import 'app.dart';
import 'data/storage.dart';
import 'llm/proxy_llm_gateway.dart';
import 'ui/main_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await Storage.open();
  runApp(CookmarkApp(controller: MainController(ProxyLlmGateway(), storage)));
}
