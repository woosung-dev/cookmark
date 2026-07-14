// 냉파(cookmark) 앱 엔트리 — MVP 셸. DESIGN.md 테마 적용.
import 'package:flutter/material.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';

void main() => runApp(const CookmarkApp());

class CookmarkApp extends StatelessWidget {
  const CookmarkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '냉파',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const HomeScreen(),
    );
  }
}
