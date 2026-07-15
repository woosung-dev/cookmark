// 앱 셸 — 테마를 걸고 메인 외길을 띄운다. 화면은 메인과 레시피 북 2개뿐이다(ADR-0001).
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'theme/app_theme.dart';
import 'ui/main_controller.dart';
import 'ui/main_page.dart';

class CookmarkApp extends StatelessWidget {
  const CookmarkApp({super.key, required this.controller, this.imagePicker});

  final MainController controller;

  /// E2E가 파일 선택창을 우회할 때 주입한다.
  final Future<XFile?> Function()? imagePicker;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '냉파',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: MainPage(controller: controller, imagePicker: imagePicker),
    );
  }
}
