// 냉파 ThemeData — DESIGN.md 토큰(색·타입·컴포넌트)을 Material 3 테마로 조립
import 'package:flutter/material.dart';
import 'app_colors.dart';

/// DESIGN.md 전제: Apple식 절제(쿨 뉴트럴·단일 액센트·희소 그림자·타이트 타이포).
abstract final class AppTheme {
  static const _radiusControl = 12.0; // 버튼·입력·셀
  static const _radiusCard = 16.0; // 카드·시트

  // DESIGN.md §3 타입 스케일(px→logical). 세리프 금지, 위계는 크기·굵기·색으로.
  static const _textTheme = TextTheme(
    displaySmall: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: AppColors.text), // large-title
    titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: AppColors.text), // 네비바 타이틀
    titleMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text), // headline
    bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: AppColors.text), // body
    bodyMedium: TextStyle(fontSize: 15, color: AppColors.text), // subhead
    bodySmall: TextStyle(fontSize: 13, color: AppColors.muted), // footnote
    labelSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.muted), // caption
  );

  static ThemeData get light {
    const scheme = ColorScheme(
      brightness: Brightness.light,
      primary: AppColors.action,
      onPrimary: AppColors.onAction,
      secondary: AppColors.goFg,
      onSecondary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.text,
      error: AppColors.danger,
      onError: Colors.white,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: AppColors.bg,
      // 폰트: 웹은 Pretendard 웹폰트 후속 반영. 우선 시스템 기본.
      textTheme: _textTheme,
      dividerTheme: const DividerThemeData(color: AppColors.hairline, thickness: 1, space: 1),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bg,
        foregroundColor: AppColors.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.text),
      ),
      // 주 CTA = 액션 홍시, radius 12, 그림자 없음
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.action,
          foregroundColor: AppColors.onAction,
          minimumSize: const Size.fromHeight(52), // 터치 ≥44
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radiusControl)),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
      ),
      // secondary = 아웃라인
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          minimumSize: const Size.fromHeight(48),
          side: const BorderSide(color: AppColors.hairline),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(_radiusControl)),
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0, // 단일-그림자 철학: 카드 flat
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_radiusCard),
          side: const BorderSide(color: AppColors.hairline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.sunken,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_radiusControl),
          borderSide: BorderSide.none,
        ),
        hintStyle: const TextStyle(color: AppColors.muted),
      ),
    );
  }
}
