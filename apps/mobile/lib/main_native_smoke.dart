// 네이티브 관통 스모크(#134 타당성 게이트) — 파일럿 게이트웨이(ProxyLlmGateway→Vercel 프록시)로
// 부팅 즉시 번들 사진을 recognize→match에 태워 "네이티브 → 프록시 → 실 Gemini" 관통을 화면으로 증명한다.
// 파일럿 빌드(main.dart)에는 포함되지 않는 throwaway다. 실행:
//   flutter build apk --debug -t lib/main_native_smoke.dart \
//     --dart-define=COOKMARK_API_BASE=https://cookmark-woosungdevs-projects.vercel.app
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '_spike_photo.dart';
import 'app.dart';
import 'data/storage.dart';
import 'domain/recipe.dart';
import 'llm/proxy_llm_gateway.dart';
import 'ui/backup_controller.dart';
import 'ui/main_controller.dart';
import 'ui/recipe_book_controller.dart';

/// 인식될 채소(가지·양파·당근)와 겹치는 실제 유튜브 레시피 — 매칭 카드가 뜨도록 심는다.
const _seedRecipes = <Recipe>[
  Recipe(
    url: 'https://www.youtube.com/watch?v=ZsvevWrQ6M0',
    title: '가지볶음',
    ingredients: ['가지', '양파', '간장', '다진 마늘'],
  ),
  Recipe(
    url: 'https://www.youtube.com/watch?v=nQaR6cwSmQk',
    title: '가지덮밥',
    ingredients: ['가지', '양파', '간장', '밥'],
  ),
  Recipe(
    url: 'https://www.youtube.com/watch?v=aOsxjAfXwIA',
    title: '채소볶음',
    ingredients: ['당근', '양파', '가지', '소금'],
  ),
];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final storage = await Storage.open();
  await storage.writeRecipes(_seedRecipes);

  final gateway = ProxyLlmGateway();
  final controller = MainController(gateway, storage);

  // 부팅 즉시 파일럿 프록시를 관통한다 — recognize(사진→재료) 후 곧바로 match(→제안 3개)까지.
  final photo = base64Decode(spikePhotoBase64);
  unawaited(
    controller.uploadPhoto(photo).then((_) => controller.requestSuggestions()),
  );

  runApp(
    CookmarkApp(
      controller: controller,
      recipeBookController: RecipeBookController(gateway, storage),
      backupController: BackupController(storage),
    ),
  );
}
