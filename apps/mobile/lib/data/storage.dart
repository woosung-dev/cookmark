// 클라이언트 로컬 영속의 유일한 경계 — 위젯은 스토리지 API를 직접 호출하지 않는다(coding-standards).
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/app_event.dart';
import '../domain/recipe.dart';
import '../domain/session_state.dart';

/// 이벤트 로그·레시피 북·세션 상태의 읽기/쓰기를 한 곳에 모은 모듈.
///
/// 로그인·서버 DB가 없으므로 이것이 유일한 영속층이다(스펙 #13). 웹 빌드에서는 브라우저 스토리지로
/// 내려간다 — 카톡 인앱 브라우저에서 유실될 수 있어 주간 백업(#20)이 보험이다.
class Storage {
  Storage._(this._prefs);

  final SharedPreferencesWithCache _prefs;

  static const _kEvents = 'events';
  static const _kSession = 'session';
  static const _kRecipes = 'recipes';
  static const _kLastBackupAt = 'lastBackupAt';
  static const _kExpectationSeen = 'expectationNoteSeen';

  static const _allowList = <String>{
    _kEvents,
    _kSession,
    _kRecipes,
    _kLastBackupAt,
    _kExpectationSeen,
  };

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
      // 못 읽는 유형은 조용히 빠진다 — 디스크의 원본은 그대로다(appendEvent 참조).
      for (final e in list)
        ?AppEvent.parse((e! as Map).cast<String, Object?>()),
    ];
  }

  /// 로그에 덧붙인다 — 읽어서 다시 쓰지 않는다. 못 읽는 이벤트가 있어도 쓰기가 막히지 않고,
  /// 그 원본도 지워지지 않는다. 로그는 덧붙이기만 한다.
  Future<void> appendEvent(AppEvent event) async {
    final raw = _prefs.getString(_kEvents);
    final stored = raw == null
        ? const <Object?>[]
        : jsonDecode(raw) as List<Object?>;
    await _prefs.setString(_kEvents, jsonEncode([...stored, event.toJson()]));
  }

  SessionState? readSession() {
    final raw = _prefs.getString(_kSession);
    if (raw == null) return null;
    return SessionState.fromJson(
      (jsonDecode(raw) as Map).cast<String, Object?>(),
    );
  }

  Future<void> writeSession(SessionState session) =>
      _prefs.setString(_kSession, jsonEncode(session.toJson()));

  /// 레시피 북 — 저장한 순서 그대로.
  /// 서버 모드(#121)에선 여기(read/write)가 서버 응답의 미러다 — 진실원은 서버, 여긴 동기 read용 렌더 버퍼.
  List<Recipe> readRecipes() {
    final raw = _prefs.getString(_kRecipes);
    if (raw == null) return const [];
    return [
      for (final r in jsonDecode(raw) as List<Object?>)
        Recipe.fromJson((r! as Map).cast<String, Object?>()),
    ];
  }

  Future<void> writeRecipes(List<Recipe> recipes) => _prefs.setString(
    _kRecipes,
    jsonEncode([for (final r in recipes) r.toJson()]),
  );

  /// "자주 쓰는 재료" 칩의 재료 — 사용자가 있다고 말한 횟수가 많은 순(#15).
  ///
  /// 빈도의 출처는 이벤트 로그다. 추가(add)와 재체크(recheck)만 센다 — 둘 다 "이건 우리 집에 있다"는
  /// 사용자의 진술이다. 해제(uncheck)는 없다는 진술이므로 세지 않는다.
  /// 로그가 비어 있으면 빈 목록이다 — 빈도는 이력에서만 나온다.
  List<String> frequentIngredients({int limit = 8}) {
    final counts = <String, int>{};
    for (final event in readEvents()) {
      if (event.type != AppEventType.checklistEdit) continue;
      final kind = event.data['kind'];
      if (kind != EditKind.add.name && kind != EditKind.recheck.name) continue;
      final name = event.data['name'] as String?;
      if (name == null) continue;
      counts[name] = (counts[name] ?? 0) + 1;
    }

    final names = counts.keys.toList()
      ..sort((a, b) {
        final byCount = counts[b]!.compareTo(counts[a]!);
        // 동률이면 이름순 — 칩 순서가 매번 흔들리면 근육 기억이 안 생긴다.
        return byCount != 0 ? byCount : a.compareTo(b);
      });
    return names.take(limit).toList();
  }

  /// 기대 세팅 문구를 이미 봤는가 — 1회성이다(G1 #8).
  bool readExpectationNoteSeen() => _prefs.getBool(_kExpectationSeen) ?? false;

  Future<void> markExpectationNoteSeen() =>
      _prefs.setBool(_kExpectationSeen, true);

  /// 마지막으로 백업한 시각. null이면 한 번도 안 했다.
  DateTime? readLastBackupAt() {
    final raw = _prefs.getString(_kLastBackupAt);
    return raw == null ? null : DateTime.parse(raw);
  }

  Future<void> writeLastBackupAt(DateTime at) =>
      _prefs.setString(_kLastBackupAt, at.toUtc().toIso8601String());

  /// E2E가 브라우저 localStorage를 비우고 시작할 수 있게 — 앱에는 데이터를 지우는 경로가 없다.
  @visibleForTesting
  Future<void> clear() => _prefs.clear();
}
