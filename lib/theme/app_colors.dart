// 냉파 색상 토큰 — DESIGN.md(루트) §2를 Flutter Color로 매핑한 단일 소스
import 'package:flutter/material.dart';

/// DESIGN.md의 홍시(감) 퍼시먼 팔레트. 온기는 액센트에만, 뉴트럴은 쿨 클린(Apple).
abstract final class AppColors {
  // 브랜드 액센트
  static const brand = Color(0xFFE8552D); // 홍시 vivid — 필·그래픽 전용(흰 텍스트 금지)
  static const action = Color(0xFFC0391B); // 곶감브릭 — 버튼·활성·핵심(흰 텍스트, AA 5.47)
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
  static const goFg = Color(0xFF1F6B43); // 바로 가능 = 나물 그린
  static const goBg = Color(0xFFE4F1E9);
  static const buyFg = Color(0xFF8A5A12); // 이것만 사면 가능 = 앰버
  static const buyBg = Color(0xFFFBF0DA);
  static const maybeFg = Color(0xFF5B5B60); // 애매하지만 가능 = 그레이
  static const maybeBg = Color(0xFFEFEFF2);
  static const danger = Color(0xFFB23A25); // 부족 재료·에러
  static const dangerBg = Color(0xFFFBE7E2);
}
