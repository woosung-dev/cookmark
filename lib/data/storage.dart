// 클라이언트 로컬 영속의 유일한 경계 — 위젯은 스토리지 API를 직접 호출하지 않는다(coding-standards).
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/app_event.dart';

/// 이벤트 로그·레시피 북·세션 상태의 읽기/쓰기를 한 곳에 모은 모듈.
///
/// 로그인·서버 DB가 없으므로 이것이 유일한 영속층이다(스펙 #13). 웹 빌드에서는 브라우저 스토리지로
/// 내려간다 — 카톡 인앱 브라우저에서 유실될 수 있어 주간 백업(#20)이 보험이다.
class Storage {
  Storage._(this._prefs);

  final SharedPreferencesWithCache _prefs;

  static const _kEvents = 'events';

  static const _allowList = <String>{_kEvents};

  static Future<Storage> open() async {
    final prefs = await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(
        allowList: _allowList,
      ),
    );
    return Storage._(prefs);
  }

  /// 기록된 순서 그대로의 이벤트 로그. 업로드 세션(30분 윈도)은 저장 단위가 아니라
  /// 분석 시 타임스탬프에서 파생한다(스펙 #13).
  List<AppEvent> readEvents() {
    final raw = _prefs.getString(_kEvents);
    if (raw == null) return const [];
    final list = jsonDecode(raw) as List<Object?>;
    return [
      for (final e in list)
        AppEvent.fromJson((e! as Map).cast<String, Object?>()),
    ];
  }

  Future<void> appendEvent(AppEvent event) async {
    final events = [...readEvents(), event];
    await _prefs.setString(
      _kEvents,
      jsonEncode([for (final e in events) e.toJson()]),
    );
  }
}
