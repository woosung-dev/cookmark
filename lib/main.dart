// 냉파 앱 엔트리 — 의존성(스토리지·LLM 경계)을 여기서 한 번 조립한다
import 'package:flutter/material.dart';

import 'data/app_storage.dart';
import 'llm/gemini_proxy_recognizer.dart';
import 'llm/recognizer.dart';
import 'screens/main_controller.dart';
import 'screens/main_page.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(CookmarkApp(storage: await AppStorage.open()));
}

/// 앱 루트. [recognizer]를 넘기지 않으면 실제 서버리스 프록시를 쓴다 —
/// E2E는 여기에 결정적 페이크를 주입한다(스펙 #13의 유일한 seam).
class CookmarkApp extends StatefulWidget {
  const CookmarkApp({required this.storage, this.recognizer, super.key});

  final AppStorage storage;
  final IngredientRecognizer? recognizer;

  @override
  State<CookmarkApp> createState() => _CookmarkAppState();
}

class _CookmarkAppState extends State<CookmarkApp> {
  late final MainController _controller = MainController(
    storage: widget.storage,
    recognizer: widget.recognizer ?? GeminiProxyRecognizer.forApp(),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '냉파',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: MainPage(controller: _controller),
    );
  }
}
