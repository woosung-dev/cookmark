// 하단 탭 셸 — 메인 외길 + 레시피 북 두 탭(ADR-0007, ADR-0001 역전). 파일럿 풀 패리티.
//
// 상태(체크리스트·제안·레시피)는 컨트롤러가 들고 있어 탭을 오가도 그대로 복원된다 —
// 선택된 탭만 빌드해도 되므로 화면 트리가 단순하고 finder 의미가 명확하다.
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'backup_controller.dart';
import 'main_controller.dart';
import 'main_page.dart';
import 'recipe_book_controller.dart';
import 'recipe_book_page.dart';

class RootShell extends StatefulWidget {
  const RootShell({
    super.key,
    required this.controller,
    required this.recipeBookController,
    required this.backupController,
    this.imagePicker,
  });

  final MainController controller;
  final RecipeBookController recipeBookController;
  final BackupController backupController;
  final Future<XFile?> Function()? imagePicker;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  void _select(int i) {
    if (_index != i) setState(() => _index = i);
    // 레시피 북에서 뭔가 바뀌었을 수 있다 — 미인식 칩·넛지가 이걸 따라간다.
    widget.controller.refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _index == 0
          ? MainPage(
              controller: widget.controller,
              recipeBookController: widget.recipeBookController,
              backupController: widget.backupController,
              imagePicker: widget.imagePicker,
              onOpenRecipeBook: () => _select(1),
            )
          : RecipeBookPage(
              controller: widget.recipeBookController,
              backupController: widget.backupController,
            ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '메인',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmark_outline),
            selectedIcon: Icon(Icons.bookmark),
            label: '레시피 북',
          ),
        ],
      ),
    );
  }
}
