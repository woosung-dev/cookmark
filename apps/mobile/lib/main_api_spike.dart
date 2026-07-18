// 라이브 스모크 도구 — recognize·match가 apps/api FastAPI(/api/v1/llm/*)를 실제로 관통하는지 확인한다.
//
// 부팅 즉시 번들 사진으로 recognize를 태워 "브라우저 → FastAPI → Gemini" 관통을 화면으로 보인다.
// 파일럿 빌드(main.dart)에는 포함되지 않는다. 실행:
//   flutter build web -t lib/main_api_spike.dart \
//     --dart-define=COOKMARK_API_BASE=http://localhost:8099 \
//     --dart-define=COOKMARK_SESSION_TOKEN=<세션 토큰>
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '_spike_photo.dart';
import 'app.dart';
import 'data/storage.dart';
import 'domain/recipe.dart';
import 'llm/api_v1_llm_gateway.dart';
import 'ui/backup_controller.dart';
import 'ui/main_controller.dart';
import 'ui/recipe_book_controller.dart';

const _base = String.fromEnvironment('COOKMARK_API_BASE');
const _token = String.fromEnvironment('COOKMARK_SESSION_TOKEN');

/// 매칭 카드가 "내 레시피 북" 출처로 뜨고 og:image 썸네일이 붙도록, 인식될 채소와 겹치는
/// 실제 요리 유튜브 레시피를 심는다.
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

  final gateway = ApiV1LlmGateway(baseUrl: _base, sessionToken: _token);
  final controller = MainController(gateway, storage);

  // 부팅 즉시 실제 FastAPI를 관통한다 — recognize(사진→재료) 후 곧바로 match(→제안 3개)까지.
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
