// DESIGN.md의 타이포·스페이싱·라운드·깊이 토큰과 앱 ThemeData — 값의 정본은 DESIGN.md다.
import 'package:flutter/material.dart';

import 'app_colors.dart';

/// 4/8 스페이싱 스케일. DESIGN.md `spacing`.
abstract final class Space {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;

  /// 화면 좌우 여백.
  static const screenPad = 16.0;

  /// 리스트 행 최소 높이.
  static const rowMin = 52.0;

  /// 터치 타깃 최소.
  static const touchMin = 44.0;
}

/// 한 라운드 스케일로 잠금. DESIGN.md `rounded`.
abstract final class Radii {
  static const chip = 8.0;
  static const control = 12.0;
  static const card = 16.0;
  static const photo = 12.0;
  static const pill = 9999.0;
}

/// Apple 단일-그림자 철학 — 기본은 flat이고 그림자는 업로드한 냉장고 사진에만.
abstract final class Elevations {
  static const List<BoxShadow> flat = [];
  static const List<BoxShadow> photo = [
    BoxShadow(
      color: Color(0x1A1D1D1F), // rgba(29,29,31,.10)
      blurRadius: 20,
      offset: Offset(0, 6),
    ),
  ];
}

abstract final class AppTypography {
  /// DESIGN.md `typography.sans` — 앞의 것부터 있으면 쓴다.
  static const sans = 'SF Pro Display';
  static const sansFallback = <String>[
    'SF Pro Text',
    'Pretendard',
    'IBM Plex Sans KR',
    'system-ui',
  ];

  /// DESIGN.md `typography.mono` — 수치(0/3 카운터·부족 재료 수·측정 푸터)에만.
  static const mono = 'IBM Plex Mono';
  static const monoFallback = <String>['ui-monospace', 'monospace'];

  static const largeTitle = TextStyle(
    fontFamily: sans,
    fontFamilyFallback: sansFallback,
    fontSize: 30,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.4,
    color: AppColors.text,
  );

  static const title = TextStyle(
    fontFamily: sans,
    fontFamilyFallback: sansFallback,
    fontSize: 20,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
    color: AppColors.text,
  );

  static const headline = TextStyle(
    fontFamily: sans,
    fontFamilyFallback: sansFallback,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    color: AppColors.text,
  );

  static const body = TextStyle(
    fontFamily: sans,
    fontFamilyFallback: sansFallback,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 1.5,
    color: AppColors.text,
  );

  static const subhead = TextStyle(
    fontFamily: sans,
    fontFamilyFallback: sansFallback,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: AppColors.text,
  );

  static const footnote = TextStyle(
    fontFamily: sans,
    fontFamilyFallback: sansFallback,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: AppColors.text,
  );

  static const caption = TextStyle(
    fontFamily: sans,
    fontFamilyFallback: sansFallback,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: AppColors.text,
  );

  /// tabular figures — 자릿수가 흔들리지 않게.
  static const numeric = TextStyle(
    fontFamily: mono,
    fontFamilyFallback: monoFallback,
    fontSize: 13,
    fontWeight: FontWeight.w400,
    fontFeatures: [FontFeature.tabularFigures()],
    color: AppColors.text,
  );
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme.light(
    primary: AppColors.action,
    onPrimary: AppColors.onAction,
    secondary: AppColors.brand,
    onSecondary: AppColors.onAction,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    error: AppColors.danger,
    onError: AppColors.onAction,
    outlineVariant: AppColors.hairline,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    fontFamily: AppTypography.sans,
    fontFamilyFallback: AppTypography.sansFallback,
    splashFactory: NoSplash.splashFactory,
    textTheme: const TextTheme(
      headlineLarge: AppTypography.largeTitle,
      titleLarge: AppTypography.title,
      titleMedium: AppTypography.headline,
      bodyLarge: AppTypography.body,
      bodyMedium: AppTypography.subhead,
      bodySmall: AppTypography.footnote,
      labelSmall: AppTypography.caption,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: AppTypography.title,
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.hairline,
      thickness: 1,
      space: 1,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.action,
        foregroundColor: AppColors.onAction,
        disabledBackgroundColor: AppColors.hairline,
        disabledForegroundColor: AppColors.muted,
        elevation: 0,
        textStyle: AppTypography.headline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(Radii.control)),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.hairline),
        textStyle: AppTypography.headline,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(Radii.control)),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.action,
        textStyle: AppTypography.headline,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.sunken,
      hintStyle: AppTypography.body.copyWith(color: AppColors.muted),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.md,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.control),
        borderSide: BorderSide.none,
      ),
    ),
  );
}
