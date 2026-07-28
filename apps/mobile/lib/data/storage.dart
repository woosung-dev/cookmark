// 클라이언트 로컬 영속의 유일한 경계 — 위젯은 스토리지 API를 직접 호출하지 않는다(coding-standards).
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/app_event.dart';
import '../domain/recipe.dart';
import '../domain/session_state.dart';

/// 이벤트 로그·레시피 북·세션 상태·등록 토큰의 읽기/쓰기를 한 곳에 모은 모듈.
///
/// 로그인 화면이 없으므로(ADR-0012) 이것이 유일한 영속층이다(스펙 #13). 웹 빌드에서는 브라우저
/// 스토리지로 내려간다 — 카톡 인앱 브라우저에서 유실될 수 있어 주간 백업(#20)이 보험이다.
///
/// 백킹 스토어는 **둘**이다 — 대부분은 `shared_preferences`이고 등록 토큰만 기기 보안 저장소다
/// (Keychain/Keystore, `backend.md` §9). 스토어가 갈려도 **경계는 하나**라는 것이 요점이다(AGENTS.md).
class Storage {
  Storage._(this._prefs);

  final SharedPreferencesWithCache _prefs;

  /// 등록 토큰 전용 백킹. 테스트는 `FlutterSecureStorage.setMockInitialValues({})`로 인메모리
  /// 플랫폼을 꽂는다 — `SharedPreferencesAsyncPlatform.instance`를 갈아끼우는 기존 관용구와 동형이고,
  /// 그래서 갈아끼우기 위한 인터페이스를 따로 만들지 않았다(`mobile.md` §2-1·§8).
  final FlutterSecureStorage _secure = const FlutterSecureStorage();

  static const _kDeviceToken = 'cookmark.deviceToken';

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
    // localStorage는 배포를 가로질러 산다 — 손상·스키마 드리프트가 부팅을 막으면 안 된다.
    // 읽기는 강등만 한다. 디스크의 원본은 그대로다(appendEvent 참조).
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];
    final events = <AppEvent>[];
    for (final e in decoded) {
      try {
        // 못 읽는 유형은 parse가 null을 주고, 손상 항목은 throw한다 — 둘 다 조용히 빠진다.
        final event = AppEvent.parse((e! as Map).cast<String, Object?>());
        if (event != null) events.add(event);
      } catch (_) {
        // 이 항목만 건너뛴다.
      }
    }
    return events;
  }

  /// 로그에 덧붙인다 — 읽어서 다시 쓰지 않는다. 못 읽는 이벤트가 있어도 쓰기가 막히지 않고,
  /// 그 원본도 지워지지 않는다. 로그는 덧붙이기만 한다.
  Future<void> appendEvent(AppEvent event) async {
    final raw = _prefs.getString(_kEvents);
    // 손상·비-List blob이면 이어 붙일 원본이 없으니 새 로그로 시작한다 — 쓰기가 throw해서
    // 코어 루프(사진 업로드부터)가 조용히 죽는 것보다 낫다. readEvents가 이미 []로 강등하는
    // 그 원본이라 복구할 것도 없다. 정상 blob은 그대로 이어 붙인다(못 읽는 미래 스키마도 보존).
    List<Object?> stored = const [];
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) stored = decoded;
      } on FormatException {
        // 손상 blob — stored는 빈 목록으로 두고 새 로그를 시작한다.
      }
    }
    await _prefs.setString(_kEvents, jsonEncode([...stored, event.toJson()]));
  }

  SessionState? readSession() {
    final raw = _prefs.getString(_kSession);
    if (raw == null) return null;
    try {
      return SessionState.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>(),
      );
    } catch (_) {
      // 손상·필드 결손이면 세션 없음으로 강등한다 — 부팅이 계속된다. 원본은 지우지 않는다.
      return null;
    }
  }

  Future<void> writeSession(SessionState session) =>
      _prefs.setString(_kSession, jsonEncode(session.toJson()));

  /// 레시피 북 — 저장한 순서 그대로.
  /// 서버 모드(#121)에선 여기(read/write)가 서버 응답의 미러다 — 진실원은 서버, 여긴 동기 read용 렌더 버퍼.
  List<Recipe> readRecipes() {
    final raw = _prefs.getString(_kRecipes);
    if (raw == null) return const [];
    // 매 build가 동기 호출하는 경로다 — 손상 한 건이 앱 전체를 던지면 안 된다(readEvents와 동형).
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return const [];
    }
    if (decoded is! List) return const [];
    final recipes = <Recipe>[];
    for (final r in decoded) {
      try {
        recipes.add(Recipe.fromJson((r! as Map).cast<String, Object?>()));
      } catch (_) {
        // 손상 항목만 건너뛴다 — 파싱 가능한 것은 살린다. 원본은 지우지 않는다.
      }
    }
    return recipes;
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

  /// 익명 기기 등록 토큰 — 없으면 아직 등록한 적이 없다(ADR-0012).
  ///
  /// 다른 read와 달리 **async**다. 백킹이 보안 저장소라 동기 캐시가 성립하지 않고, 유일한 소비자
  /// (기기 세션 경계)가 이미 async라 캐시할 이유도 없다. [open]에서 미리 읽지 않는 것은 의도다 —
  /// E2E의 이벤트 대기 헬퍼가 폴링마다 [open]을 부르는데 거기에 크립토 왕복을 붙일 이유가 없다.
  Future<String?> readDeviceToken() => _secure.read(key: _kDeviceToken);

  Future<void> writeDeviceToken(String token) =>
      _secure.write(key: _kDeviceToken, value: token);

  /// D0 직전 기록 초기화 — **레시피 빼고 다** 지운다(#144, 절차 #41).
  ///
  /// 베이스라인 구간의 기술 관통 테스트가 만든 이벤트가 파일럿 데이터에 섞이면 지표 1(자발 사용)이
  /// 부풀고 P2 킬 기준(수동 수정 주 평균)이 테스트 조작으로 오염된다. 레시피 북은 파일럿의 **입력**이라
  /// 살아남아야 한다 — 지우면 파운더가 배우자의 레시피를 다시 넣어야 하고 그건 D0 당일에 할 일이 아니다.
  ///
  /// 세션·백업 시각·1회성 플래그를 이벤트와 함께 지우는 이유는 셋 다 "이번 파일럿 런"의 수명을 갖기
  /// 때문이다. 특히 세션을 남기면 초기화 직후 재부팅에서 [readSession]이 관통 테스트의 체크리스트를
  /// 되살려 리셋이 눈에 보이게 깨진다.
  ///
  /// [clear]와 **일부러 별개 API**다 — 그쪽은 레시피까지 날리는 테스트 전용 경로다.
  ///
  /// 지울 키를 열거하지 않고 [_allowList]에서 레시피만 뺀다 — 계약이 "레시피 빼고 다"이므로
  /// 새 키가 생기면 **지워지는 쪽이 기본값**이어야 문서와 코드가 갈라지지 않는다. 열거식이면
  /// 새 키가 조용히 살아남아 다음 파일럿 런으로 새어나간다. 보존이 필요한 키가 생기면
  /// 여기 예외 집합에 넣도록 강제되고, 키 단위 유닛 테스트가 그 결정을 표면화한다.
  ///
  /// **등록 토큰도 보존한다**(#168) — 갈아치우면 다음 부팅이 새 계정을 받아 서버 레시피 북이
  /// 통째로 고아가 된다. 토큰은 백킹 스토어가 갈려 [_allowList] 밖에 살지만 **판정은 여기서**
  /// 한다 — "레시피 빼고 다"의 의미를 이 모듈이 쥔다는 성질이 스토어 수와 무관해야 한다.
  ///
  /// ⚠️ **보안 저장소 쪽은 기본값이 반대다** — 여기서 손대지 않으므로 "살아남는 쪽"이 기본이고,
  /// 위 [_allowList]의 subtractive 정책이 그쪽을 안 덮는다. 지금은 그 스토어에 값이
  /// [_kDeviceToken] 하나뿐이라 성립한다. **둘째 값을 넣는 사람이 이 결정을 다시 해야 한다** —
  /// 그때 지워야 할 값이면 여기에 명시적으로 추가한다.
  Future<void> clearPilotRecord() => Future.wait([
    for (final key in _allowList.difference(_preservedOnReset))
      _prefs.remove(key),
  ]);

  /// 기록 초기화가 살려두는 키 — 레시피 북은 파일럿의 **입력**이라 살아남아야 한다(#144).
  /// 등록 토큰은 다른 스토어에 살아 이 집합에 못 들어가지만 같은 이유로 보존된다([clearPilotRecord]).
  static const _preservedOnReset = <String>{_kRecipes};

  /// E2E가 브라우저 스토리지를 비우고 시작할 수 있게 — 레시피도 등록 토큰도 날린다.
  /// 앱 안에서 파운더가 쓰는 초기화는 [clearPilotRecord]다.
  @visibleForTesting
  Future<void> clear() async {
    await _prefs.clear();
    await _secure.delete(key: _kDeviceToken);
  }
}
