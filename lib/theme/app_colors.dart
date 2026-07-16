// DESIGN.md의 색 토큰을 그대로 옮긴 팔레트 — 값의 정본은 DESIGN.md이고 여기서 새 색을 만들지 않는다.
import 'package:flutter/widgets.dart';

abstract final class AppColors {
  // 브랜드 액센트 (단일, 절제)
  /// 홍시(감) 퍼시먼 — 로고·히어로·큰 필. 대비 3.6이라 흰 텍스트를 얹지 않는다.
  static const brand = Color(0xFFE8552D);

  /// 곶감브릭 — 버튼·활성·핵심 어포던스. 흰 텍스트 AA(5.47).
  static const action = Color(0xFFC0391B);
  static const actionPressed = Color(0xFF9A2E15);
  static const actionTint = Color(0xFFFBE7E2);
  static const onAction = Color(0xFFFFFFFF);

  // 뉴트럴 (쿨 클린 — 크림 금지)
  static const bg = Color(0xFFF5F5F7);
  static const surface = Color(0xFFFFFFFF);
  static const text = Color(0xFF1D1D1F);
  static const muted = Color(0xFF6E6E73);
  static const hairline = Color(0xFFD2D2D7);
  static const sunken = Color(0xFFEDEDF0);

  // 시맨틱 — 제안 라벨(색+아이콘 이중 신호)
  /// 바로 가능 = 나물 그린
  static const goFg = Color(0xFF1F6B43);
  static const goBg = Color(0xFFE4F1E9);

  /// 이것만 사면 가능 = 앰버
  static const buyFg = Color(0xFF8A5A12);
  static const buyBg = Color(0xFFFBF0DA);

  /// 애매하지만 가능 = 그레이
  static const maybeFg = Color(0xFF5B5B60);
  static const maybeBg = Color(0xFFEFEFF2);

  // 부족 재료·에러
  static const danger = Color(0xFFB23A25);
  static const dangerBg = Color(0xFFFBE7E2);
}
