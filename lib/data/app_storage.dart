// 로컬 영속의 단일 경계 — 이벤트 로그·세션 상태의 유일한 읽기/쓰기 지점(위젯에서 직접 호출 금지)
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_event.dart';
import '../models/ingredient.dart';

/// 클라이언트 로컬 영속의 단일 모듈. 로그인·서버 DB가 없으므로 이것이 유일한
/// 영속층이고(코딩 스탠다드), Web 빌드에서는 브라우저 스토리지로 내려간다.
///
/// 읽기는 메모리 캐시에서 동기로 답하고, 쓰기만 비동기로 내려쓴다 —
/// 냉장고 앞에서 쓰는 앱이라 렌더가 스토리지를 기다리면 안 된다.
class AppStorage {
  AppStorage._(this._prefs, this._events, this._session);

  static const _eventsKey = 'cookmark.events';
  static const _sessionKey = 'cookmark.session';

  final SharedPreferences _prefs;
  final List<AppEvent> _events;
  List<Ingredient> _session;

  static Future<AppStorage> open() async {
    final prefs = await SharedPreferences.getInstance();
    return AppStorage._(
      prefs,
      _decodeList(prefs.getString(_eventsKey), AppEvent.fromJson),
      _decodeList(prefs.getString(_sessionKey), _ingredientFromJson),
    );
  }

  /// 지금까지 쌓인 이벤트를 시간 순으로 돌려준다(주간 백업 export의 원천).
  List<AppEvent> get events => List.unmodifiable(_events);

  /// 마지막 세션의 재료 체크리스트. 없으면 빈 목록.
  List<Ingredient> get session => List.unmodifiable(_session);

  Future<void> appendEvent(AppEvent event) async {
    _events.add(event);
    await _prefs.setString(
      _eventsKey,
      jsonEncode(_events.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> saveSession(List<Ingredient> ingredients) async {
    _session = List.of(ingredients);
    await _prefs.setString(
      _sessionKey,
      jsonEncode(_session.map(_ingredientToJson).toList()),
    );
  }

  Future<void> clearSession() async {
    _session = [];
    await _prefs.remove(_sessionKey);
  }

  /// 손상된 JSON에 로그 전체를 잃지 않는다 — 파일럿 데이터는 복구 불가이므로
  /// 읽기 실패는 빈 목록으로 흡수하고 이후 append는 계속 살린다.
  static List<T> _decodeList<T>(
    String? raw,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map((e) => fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (e) {
      debugPrint('cookmark: 저장된 데이터를 읽지 못해 건너뜁니다 — $e');
      return [];
    }
  }

  static Map<String, dynamic> _ingredientToJson(Ingredient i) => {
    'name': i.name,
    'confidence': i.confidence.name,
    'checked': i.checked,
  };

  static Ingredient _ingredientFromJson(Map<String, dynamic> json) =>
      Ingredient(
        name: json['name'] as String,
        confidence: Confidence.parse(json['confidence'] as String?),
        checked: json['checked'] as bool? ?? false,
      );
}
