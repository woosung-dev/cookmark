// 파일럿 export JSON을 킬 기준·성공 지표로 환산하는 파운더 판정 CLI (ADR-0003·0004, 스펙 #13).
//
// 실행: dart run tool/analyze_pilot.dart [옵션] <export1.json> [export2.json ...]
//   파일 1개 = 기기 1대(파운더/배우자). 여러 개 = 가구 단위 합산(스펙 US 30).
//   각 기기당 "가장 최신 누적 export 하나"만 넣는다 — 같은 기기의 주간 파일을 여러 개 넣으면
//   이벤트가 이중 계상된다(로그는 append-only라 최신 파일이 전체를 담는다).
//
// 옵션:
//   --d0=<ISO8601>   파일럿 D0(주 버킷의 앵커). 기본 2026-07-22T18:00:00+09:00 (ADR-0005 #31 재서명).
//   --gap=<분>       업로드 세션 윈도. 기본 30 (CONTEXT.md "업로드 세션").
//   --weeks=<n>      파일럿 설계 주 수(표시용). 기본 2.
//
// 이 툴은 Flutter에 의존하지 않는다(파운더가 `dart run`으로 바로 실행). 대신 이벤트 `type`/`kind`
// 이름 집합을 알고 있고, test/tool/analyze_pilot_test.dart가 그 집합을 실제 AppEventType/EditKind
// enum과 대조한다 — app_event.dart가 "이 열거형은 분석의 계약"이라 못박은 그 계약의 드리프트 가드다.

import 'dart:convert';
import 'dart:io';

// ── 판정 임계값 (파일럿 중 불변, 정본은 ADR/CONTEXT) ──────────────────────────

/// P2 킬 기준 — 사진(=업로드 세션)당 수동 수정 주 평균이 이 값을 **초과**하면 그 주는 위험 주다.
/// 2주 연속 위험이면 킬(ADR-0003).
const killEditsPerSessionThreshold = 5.0;

/// P2 킬 발화에 필요한 연속 위험 주 수(ADR-0003).
const killConsecutiveWeeks = 2;

/// 자발 사용 지표 — 주당 업로드 세션이 이 값 이상이면 "자발 사용"으로 본다(스펙 #13 지표 1).
const voluntaryUseSessionsPerWeek = 3;

/// 업로드 세션 윈도 기본값 — 이보다 긴 간격이면 새 세션(CONTEXT.md "업로드 세션").
const defaultSessionGapMinutes = 30;

/// 파일럿 D0 기본값 — ADR-0005 #31 재서명(배포 7/16·베이스라인 7/15 시작 → D0=7/22 저녁).
const defaultD0 = '2026-07-22T18:00:00+09:00';

// ── 이벤트 계약(드리프트 가드가 실 enum과 대조한다) ─────────────────────────────

/// 이벤트 카탈로그 12종의 이름 — AppEventType.values 의 name 과 정확히 일치해야 한다.
const knownEventTypes = <String>{
  'photoUpload',
  'recognitionDone',
  'checklistEdit',
  'matchingDone',
  'suggestionsShown',
  'suggestionOpened',
  'cooked',
  'cookedUndo',
  'rematch',
  'recipeBookChanged',
  'backup',
  'errorShown',
};

/// 체크리스트 조작 유형 — EditKind.values 의 name 과 정확히 일치해야 한다(ADR-0003).
const knownEditKinds = <String>{
  'uncheck',
  'recheck',
  'add',
  'substitute',
  'vagueDismiss',
};

/// 정본 P2 산식에서 제외해 재산하는 유형(ADR-0003 — 마찰이 아니라 모델/휴리스틱 소음이라는 대안 관점).
const excludedFromStrictFormula = <String>{'recheck', 'vagueDismiss'};

// ── 파싱 ────────────────────────────────────────────────────────────────────

/// 이벤트 1건 — 와이어 계약(AppEvent.toJson)의 평평한 맵: {type, at, ...data}.
class PilotEvent {
  PilotEvent({required this.type, required this.at, required this.data});

  final String type;
  final DateTime at; // UTC
  final Map<String, Object?> data;

  static PilotEvent? parse(Map<String, Object?> json) {
    final type = json['type'];
    final at = json['at'];
    if (type is! String || at is! String) return null;
    return PilotEvent(type: type, at: DateTime.parse(at).toUtc(), data: json);
  }
}

/// export 파일 하나의 이벤트 목록. 못 읽는 이벤트는 조용히 건너뛴다(backup.dart와 같은 관용구).
List<PilotEvent> readBackupEvents(String jsonText) {
  final root = jsonDecode(jsonText);
  if (root is! Map || root['events'] is! List) {
    throw const FormatException('export JSON에 events 배열이 없다');
  }
  final out = <PilotEvent>[];
  for (final e in root['events'] as List) {
    if (e is Map) {
      final ev = PilotEvent.parse(e.cast<String, Object?>());
      if (ev != null) out.add(ev);
    }
  }
  return out;
}

// ── 집계 ────────────────────────────────────────────────────────────────────

/// 한 주(週) 안의 한 기기 지표.
class WeekMetrics {
  int photoUploads = 0;
  int sessions = 0;
  final Map<String, int> editsByKind = {};
  int cookedFresh = 0; // stale=false — 냉파發 후보
  int cookedStale = 0; // stale=true — 성공 지표 2에서 분리
  int suggestionOpened = 0;
  int rematch = 0;
  final Map<String, int> errorsByKind = {};
  double costUsd = 0;

  int get editsTotal => editsByKind.values.fold(0, (a, b) => a + b);

  int get editsStrict =>
      editsTotal -
      excludedFromStrictFormula.fold(0, (a, k) => a + (editsByKind[k] ?? 0));

  /// 정본 P2 산식 — 사진당 수동 수정. 세션이 0이면 정의 불가(null).
  double? get editsPerSession => sessions == 0 ? null : editsTotal / sessions;

  /// ADR-0003 대안 산식 — recheck·vagueDismiss 제외.
  double? get editsPerSessionStrict =>
      sessions == 0 ? null : editsStrict / sessions;

  bool get atRisk =>
      editsPerSession != null &&
      editsPerSession! > killEditsPerSessionThreshold;

  bool get voluntary => sessions >= voluntaryUseSessionsPerWeek;
}

/// 한 기기(파일 하나)의 파일럿 지표 — 주 인덱스 → 지표.
class DeviceReport {
  DeviceReport(this.label);

  final String label;
  final Map<int, WeekMetrics> weeks = {};
  int preD0Events = 0; // D0 이전 이벤트 수(초기화 누락·D0 오설정 감지용)

  WeekMetrics week(int i) => weeks.putIfAbsent(i, WeekMetrics.new);
}

/// D0 앵커 기준 주 인덱스(0-based). D0 이전이면 null.
int? weekIndexOf(DateTime at, DateTime start) {
  final atUtc = at.toUtc();
  final startUtc = start.toUtc();
  if (atUtc.isBefore(startUtc)) return null;
  return atUtc.difference(startUtc).inDays ~/ 7;
}

/// 정렬된 업로드 시각들을 gap 윈도로 세션 수로 묶는다.
int countSessions(List<DateTime> uploadTimes, Duration gap) {
  if (uploadTimes.isEmpty) return 0;
  final sorted = [...uploadTimes]..sort();
  var sessions = 1;
  var last = sorted.first;
  for (final t in sorted.skip(1)) {
    if (t.difference(last) > gap) sessions++;
    last = t;
  }
  return sessions;
}

/// 이벤트 목록 → 기기 리포트. 세션은 주별 업로드를 각각 세션화한다
/// (주 경계에 걸친 30분 세션은 무시할 만한 오차).
DeviceReport aggregate({
  required String label,
  required List<PilotEvent> events,
  required DateTime start,
  required Duration gap,
}) {
  final report = DeviceReport(label);
  final uploadsByWeek = <int, List<DateTime>>{};

  for (final e in events) {
    final wi = weekIndexOf(e.at, start);
    if (wi == null) {
      report.preD0Events++;
      continue;
    }
    final w = report.week(wi);
    switch (e.type) {
      case 'photoUpload':
        w.photoUploads++;
        (uploadsByWeek[wi] ??= []).add(e.at);
      case 'checklistEdit':
        final kind = e.data['kind'];
        if (kind is String) {
          w.editsByKind[kind] = (w.editsByKind[kind] ?? 0) + 1;
        }
      case 'cooked':
        if (e.data['stale'] == true) {
          w.cookedStale++;
        } else {
          w.cookedFresh++;
        }
      case 'suggestionOpened':
        w.suggestionOpened++;
      case 'rematch':
        w.rematch++;
      case 'errorShown':
        final kind = e.data['kind'];
        if (kind is String) {
          w.errorsByKind[kind] = (w.errorsByKind[kind] ?? 0) + 1;
        }
    }
    // 원가는 usage 필드가 붙는 모든 이벤트에서 합산.
    final cost = e.data['costUsd'];
    if (cost is num) w.costUsd += cost.toDouble();
  }

  uploadsByWeek.forEach((wi, times) {
    report.week(wi).sessions = countSessions(times, gap);
  });
  return report;
}

/// 여러 기기 리포트를 가구 단위로 합산.
DeviceReport mergeHousehold(List<DeviceReport> devices) {
  final merged = DeviceReport('가구 합산');
  for (final d in devices) {
    merged.preD0Events += d.preD0Events;
    d.weeks.forEach((wi, w) {
      final m = merged.week(wi);
      m.photoUploads += w.photoUploads;
      m.sessions += w.sessions;
      w.editsByKind.forEach(
        (k, v) => m.editsByKind[k] = (m.editsByKind[k] ?? 0) + v,
      );
      m.cookedFresh += w.cookedFresh;
      m.cookedStale += w.cookedStale;
      m.suggestionOpened += w.suggestionOpened;
      m.rematch += w.rematch;
      w.errorsByKind.forEach(
        (k, v) => m.errorsByKind[k] = (m.errorsByKind[k] ?? 0) + v,
      );
      m.costUsd += w.costUsd;
    });
  }
  return merged;
}

/// 가구 합산에서 P2 킬 발화 여부 — 위험 주가 killConsecutiveWeeks 연속인 최장 구간을 찾는다.
bool p2KillFired(DeviceReport household) {
  if (household.weeks.isEmpty) return false;
  final maxWeek = household.weeks.keys.reduce((a, b) => a > b ? a : b);
  var run = 0;
  for (var i = 0; i <= maxWeek; i++) {
    final w = household.weeks[i];
    if (w != null && w.atRisk) {
      run++;
      if (run >= killConsecutiveWeeks) return true;
    } else {
      run = 0;
    }
  }
  return false;
}

// ── 리포트 렌더 ──────────────────────────────────────────────────────────────

String _f1(double? v) => v == null ? '—' : v.toStringAsFixed(1);
String _cost(double v) => '\$${v.toStringAsFixed(5)}';

String _editsBreakdown(Map<String, int> byKind) {
  if (byKind.isEmpty) return '0';
  final parts = [
    for (final k in knownEditKinds)
      if ((byKind[k] ?? 0) > 0) '$k ${byKind[k]}',
  ];
  return parts.join(', ');
}

void _renderDevice(
  StringBuffer b,
  DeviceReport d, {
  required bool isHousehold,
}) {
  b.writeln('■ ${d.label}');
  if (d.weeks.isEmpty) {
    b.writeln('  (D0 이후 이벤트 없음)');
    if (d.preD0Events > 0) {
      b.writeln('  ⚠ D0 이전 이벤트 ${d.preD0Events}건 — 초기화(#41) 확인 필요');
    }
    b.writeln();
    return;
  }
  final maxWeek = d.weeks.keys.reduce((a, b) => a > b ? a : b);
  for (var i = 0; i <= maxWeek; i++) {
    final w = d.weeks[i];
    if (w == null) continue;
    final risk = w.atRisk
        ? ' ⚠위험(>${killEditsPerSessionThreshold.toStringAsFixed(0)})'
        : '';
    b.writeln('  주 ${i + 1}:');
    b.writeln(
      '    업로드 세션 ${w.sessions} (사진 ${w.photoUploads})'
      '${isHousehold
          ? ''
          : w.voluntary
          ? '  ✓자발'
          : '  ·자발미달(<$voluntaryUseSessionsPerWeek)'}',
    );
    b.writeln('    수동 수정 ${w.editsTotal} [${_editsBreakdown(w.editsByKind)}]');
    b.writeln(
      '    P2 사진당 수정: 정본 ${_f1(w.editsPerSession)}$risk'
      ' | 제외산식(recheck·vagueDismiss 뺌) ${_f1(w.editsPerSessionStrict)}',
    );
    b.writeln(
      '    이거 했어요 ${w.cookedFresh} (stale 제외) / stale ${w.cookedStale}'
      '  ·제안열람 ${w.suggestionOpened} ·다시제안 ${w.rematch}',
    );
    if (w.errorsByKind.isNotEmpty) {
      b.writeln(
        '    오류 ${w.errorsByKind.entries.map((e) => '${e.key} ${e.value}').join(', ')}',
      );
    }
    b.writeln('    누적 원가 ${_cost(w.costUsd)}');
  }
  if (d.preD0Events > 0) {
    b.writeln(
      '  ⚠ D0 이전 이벤트 ${d.preD0Events}건 — 초기화(#41)가 됐는지 확인'
      '(정상이면 0, 재-import 백업 1건까지 무해)',
    );
  }
  b.writeln();
}

String renderReport({
  required List<DeviceReport> devices,
  required DeviceReport household,
  required DateTime start,
  required Duration gap,
  required int pilotWeeks,
}) {
  final b = StringBuffer();
  b.writeln('════════ 냉파 파일럿 판정 ════════');
  b.writeln(
    'D0(주 앵커): ${start.toLocal()}  |  세션 윈도: ${gap.inMinutes}분'
    '  |  설계 파일럿: $pilotWeeks주',
  );
  b.writeln(
    '킬 기준(ADR-0003): 사진당 수동 수정 주 평균 '
    '>${killEditsPerSessionThreshold.toStringAsFixed(0)}가 $killConsecutiveWeeks주 연속 → KILL',
  );
  b.writeln('자발 사용(지표1): 주 $voluntaryUseSessionsPerWeek회 업로드 세션 이상');
  b.writeln();

  b.writeln('──── 기기별 (자발 사용은 인별로 본다, n=2) ────');
  for (final d in devices) {
    _renderDevice(b, d, isHousehold: false);
  }

  b.writeln('──── 가구 합산 ────');
  _renderDevice(b, household, isHousehold: true);

  b.writeln('──── 판정 ────');
  final householdFired = p2KillFired(household);
  b.writeln(
    'P2 킬(가구 합산): ${householdFired ? '🔴 발화 — 사진당 수정이 2주 연속 임계 초과' : '🟢 미발화'}',
  );
  // 가구 합산은 한 사람의 지속 마찰을 상대의 저사용으로 희석할 수 있다(n=2). 인별도 본다.
  final perDevice = [
    for (final d in devices) '${d.label} ${p2KillFired(d) ? '🔴' : '🟢'}',
  ].join('  ');
  b.writeln('P2 킬(기기별, 누구든 2주 연속이면 신호): $perDevice');
  final cookedFreshTotal = household.weeks.values.fold(
    0,
    (a, w) => a + w.cookedFresh,
  );
  b.writeln(
    '성공 지표 2(행동 변화) 앞단: 이거 했어요(stale 제외) 합계 $cookedFreshTotal'
    ' — 냉파發 최종은 요리 일지 대조 필요(아래).',
  );
  b.writeln();

  b.writeln('──── JSON으로 못 재는 것 (정직하게 표시) ────');
  b.writeln('· 성공 지표 3(폐기 감소): 요리 일지·폐기 베이스라인이 정본. 이벤트 로그에 없음.');
  b.writeln('· 냉파發 최종 판정: "이거 했어요" 클릭 ↔ 요리 일지 냉파發 표기 대조로 확정(CONTEXT.md).');
  b.writeln(
    '· 자발 vs 권유(prompted): 관찰 기록의 prompted 표기로만 분리(ADR-0004). 여기 수치는 상한.',
  );
  b.writeln('════════════════════════════════');
  return b.toString();
}

// ── CLI ─────────────────────────────────────────────────────────────────────

class _Args {
  DateTime start = DateTime.parse(defaultD0);
  Duration gap = const Duration(minutes: defaultSessionGapMinutes);
  int weeks = 2;
  final files = <String>[];
}

_Args _parseArgs(List<String> argv) {
  final a = _Args();
  for (final arg in argv) {
    if (arg.startsWith('--d0=')) {
      a.start = DateTime.parse(arg.substring(5));
    } else if (arg.startsWith('--gap=')) {
      a.gap = Duration(minutes: int.parse(arg.substring(6)));
    } else if (arg.startsWith('--weeks=')) {
      a.weeks = int.parse(arg.substring(8));
    } else if (arg.startsWith('--')) {
      throw FormatException('모르는 옵션: $arg');
    } else {
      a.files.add(arg);
    }
  }
  return a;
}

void main(List<String> argv) {
  final _Args args;
  try {
    args = _parseArgs(argv);
  } on FormatException catch (e) {
    stderr.writeln('인자 오류: ${e.message}');
    exit(2);
  }

  if (args.files.isEmpty) {
    stderr.writeln(
      '사용법: dart run tool/analyze_pilot.dart [--d0=ISO] [--gap=분] '
      '[--weeks=n] <export1.json> [export2.json ...]',
    );
    exit(2);
  }

  final devices = <DeviceReport>[];
  for (final path in args.files) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('파일 없음: $path');
      exit(1);
    }
    final events = readBackupEvents(file.readAsStringSync());
    devices.add(
      aggregate(
        label: file.uri.pathSegments.last,
        events: events,
        start: args.start,
        gap: args.gap,
      ),
    );
  }

  final household = mergeHousehold(devices);
  stdout.write(
    renderReport(
      devices: devices,
      household: household,
      start: args.start,
      gap: args.gap,
      pilotWeeks: args.weeks,
    ),
  );
}
