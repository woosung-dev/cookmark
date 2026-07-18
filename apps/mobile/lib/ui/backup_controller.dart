// 백업 섹션의 상태 — 한 동작 export, 미리보기를 거치는 안전한 import(#20).
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/server_recipe_repository.dart';
import '../data/storage.dart';
import '../domain/app_event.dart';
import '../domain/backup.dart';
import 'recipe_book_controller.dart';

class BackupController extends ChangeNotifier {
  /// [server]가 null이면 로컬 모드(현행 그대로), 주어지면 가져오기 확정이 서버를 거친다(#121).
  BackupController(
    this._storage, {
    DateTime Function()? now,
    // 외부 파라미터명은 server다 — Dart 3.12 private named parameter 관용구(ApiV1LlmGateway와 동일).
    this._server,
    // 외부 파라미터명은 serverSyncState다 — 서버 모드에서 레시피 미러의 동기 상태를 읽는 seam.
    // 미러가 ready가 아니면 dedup 기준이 스테일이라 가져오기를 받지 않는다(#121 수리).
    this._serverSyncState,
    // 외부 파라미터명은 serverRehydrate다 — 가져오기 확정 후 재수화는 레시피 컨트롤러의
    // hydrate 하나로 돈다. 재수화가 실패하면 hydrate가 미러를 error로 전이시켜 위 가드가
    // 함께 닫힌다 — 미러가 stale인데 ready로 남아 재-preview가 중복 등록하는 길을 막는다.
    this._serverRehydrate,
  }) : _now = now ?? DateTime.now;

  final Storage _storage;
  final DateTime Function() _now;
  final ServerRecipeRepository? _server;
  final RecipeSyncState Function()? _serverSyncState;
  final Future<void> Function()? _serverRehydrate;

  /// 확정 대기 중인 병합 — 미리보기를 보여주고 사용자가 확정해야 반영된다(C 이식).
  MergePreview? get pendingMerge => _pendingMerge;
  MergePreview? _pendingMerge;

  /// 가져온 JSON이 백업 파일이 아니었을 때.
  String? get importError => _importError;
  String? _importError;

  /// 확정이 서버를 도는 동안 참 — 확정 버튼을 비활성해 더블탭 중복 등록을 막는다(#121 수리).
  bool get importing => _importing;
  bool _importing = false;

  /// 서버 모드인데 미러가 서버와 맞지 않은 상태 — 이때 미러 기준 dedup은 성립하지 않는다.
  bool get _serverMirrorNotReady =>
      _server != null && _serverSyncState?.call() != RecipeSyncState.ready;

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

    // 서버 모드에서 미러가 ready가 아니면 미리보기부터 받지 않는다 — 스테일 미러 기준으로
    // newRecipes를 계산하면 확정 시 서버에 중복 등록된다(#121 수리).
    if (_serverMirrorNotReady) {
      _importError = '서버의 레시피 목록과 연결된 뒤 가져올 수 있어요. 잠시 후 다시 시도해주세요.';
      notifyListeners();
      return;
    }

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

    // 확정이 이미 도는 중이면 무시 — 더블탭이 같은 배치를 두 번 등록하면 안 된다(#121 수리).
    if (_importing) return;

    // preview 후 hydrate가 끼어들어 미러가 흔들렸을 수 있다 — 확정 시점에도 다시 가드한다.
    if (_serverMirrorNotReady) {
      _importError = '서버의 레시피 목록과 연결된 뒤 가져올 수 있어요. 잠시 후 다시 시도해주세요.';
      notifyListeners();
      return;
    }

    _importing = true;
    notifyListeners();
    try {
      if (_server != null && merge.newRecipes.isNotEmpty) {
        // 서버 모드 — newRecipes만 보낸다. 서버엔 unique가 없어 dedup 책임이 클라이언트다(#104).
        try {
          await _server.importBulk(merge.newRecipes);
        } on RecipeApiFailure {
          // 원자적 등록이라 부분 반영이 없다 — pendingMerge를 유지해 다시 확정할 수 있고 미러도 불변이다.
          _importError = '가져오기에 실패했어요 — 서버에 저장되지 않았어요.';
          return;
        }
        // 서버 등록은 끝났다 — 재확정하면 같은 배치가 중복 등록되므로 여기서 커밋을 잠근다.
        _pendingMerge = null;

        // 서버가 발급한 id·삽입순이 정본이다 — 재수화는 레시피 컨트롤러의 hydrate 하나로 돈다.
        // 순단이면 hydrate가 미러를 error로 전이시키므로(가져오기 게이트도 함께 닫힌다),
        // 여기선 결과 상태만 읽어 정직하게 알린다 — 가져오기 자체는 서버에 저장 완료됐다.
        await _serverRehydrate?.call();
        if (_serverMirrorNotReady) {
          _importError = '가져오기는 서버에 저장됐어요. 목록을 새로 불러오지 못했으니, 앱을 새로고침하면 반영됩니다.';
        }

        // 가져오기는 일어났다 — 재수화 성패와 무관하게 기록을 남긴다.
        await _storage.appendEvent(
          AppEvent.backup(
            at: _now(),
            direction: BackupDirection.import,
            recipeCount: _storage.readRecipes().length,
            eventCount: _storage.readEvents().length,
            mergeSummary: merge.toSummary(),
          ),
        );
        return;
      }

      // 레시피만 갈아끼운다 — 이벤트 로그는 이 기기의 것이고, 남의 것과 섞으면 인별 귀속이 깨진다.
      await _storage.writeRecipes(merge.mergedRecipes);
      await _storage.appendEvent(
        AppEvent.backup(
          at: _now(),
          direction: BackupDirection.import,
          recipeCount: merge.mergedRecipes.length,
          eventCount: _storage.readEvents().length,
          mergeSummary: merge.toSummary(),
        ),
      );

      _pendingMerge = null;
    } finally {
      _importing = false;
      notifyListeners();
    }
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
