// 백업 섹션의 상태 — 한 동작 export, 미리보기를 거치는 안전한 import(#20).
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/storage.dart';
import '../domain/app_event.dart';
import '../domain/backup.dart';

class BackupController extends ChangeNotifier {
  BackupController(this._storage, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final Storage _storage;
  final DateTime Function() _now;

  /// 확정 대기 중인 병합 — 미리보기를 보여주고 사용자가 확정해야 반영된다(C 이식).
  MergePreview? get pendingMerge => _pendingMerge;
  MergePreview? _pendingMerge;

  /// 가져온 JSON이 백업 파일이 아니었을 때.
  String? get importError => _importError;
  String? _importError;

  /// 내보내기 — 레시피 북 + 이벤트 로그가 단일 파일이다. 복사해서 카톡으로 보낸다.
  Future<String> exportJson() async {
    final data = BackupData(
      recipes: _storage.readRecipes(),
      events: _storage.readEvents(),
      exportedAt: _now(),
    );
    final text = const JsonEncoder.withIndent('  ').convert(data.toJson());

    await _storage.appendEvent(
      AppEvent.backup(
        at: _now(),
        direction: BackupDirection.export,
        recipeCount: data.recipes.length,
        eventCount: data.events.length,
      ),
    );
    await _storage.writeLastBackupAt(_now());
    notifyListeners();
    return text;
  }

  /// 붙여넣은 JSON을 읽어 병합 미리보기를 만든다 — 아직 반영하지 않는다.
  void previewImport(String raw) {
    _importError = null;
    _pendingMerge = null;

    final BackupData incoming;
    try {
      incoming = BackupData.fromJson(
        (jsonDecode(raw) as Map).cast<String, Object?>(),
      );
    } on Object {
      // 형식이 뭐가 됐든 읽을 수 없으면 하나의 메시지로 끝낸다 — 사용자가 할 일은 같다.
      _importError = '백업 파일이 아닌 것 같아요.';
      notifyListeners();
      return;
    }

    _pendingMerge = previewMerge(
      current: BackupData(
        recipes: _storage.readRecipes(),
        events: _storage.readEvents(),
        exportedAt: _now(),
      ),
      incoming: incoming,
    );
    notifyListeners();
  }

  /// 미리보기를 확정한다 — 여기서만 데이터가 바뀐다.
  Future<void> confirmImport() async {
    final merge = _pendingMerge;
    if (merge == null) return;

    await _storage.replaceAll(
      recipes: merge.mergedRecipes,
      events: merge.mergedEvents,
    );
    await _storage.appendEvent(
      AppEvent.backup(
        at: _now(),
        direction: BackupDirection.import,
        recipeCount: merge.mergedRecipes.length,
        eventCount: merge.mergedEvents.length,
        mergeSummary: merge.toSummary(),
      ),
    );

    _pendingMerge = null;
    notifyListeners();
  }

  void cancelImport() {
    _pendingMerge = null;
    _importError = null;
    notifyListeners();
  }

  /// 7일이 지났으면 주간 성적표로 백업을 권한다(G1 #8).
  ///
  /// 한 번도 백업하지 않았다면 첫 이벤트로부터 7일을 센다 — 설치만 하고 안 쓴 사람을
  /// 첫날부터 조르지 않기 위해서다.
  bool get needsBackup {
    final last = _storage.readLastBackupAt();
    if (last != null) return _now().difference(last) >= backupReminderAfter;

    final events = _storage.readEvents();
    if (events.isEmpty) return false;
    return _now().difference(events.first.at) >= backupReminderAfter;
  }

  /// 주간 성적표 — 업로드와 이거 했어요만. 수동 수정 수는 절대 넣지 않는다(ADR-0004).
  WeeklyReport get weeklyReport =>
      weeklyReportFrom(_storage.readEvents(), _now());
}
