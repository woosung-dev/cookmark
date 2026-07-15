// 이벤트 로그가 남고 새로고침 후에도 유지되는지 — #14 AC의 영속 부분.
import 'package:cookmark/data/storage.dart';
import 'package:cookmark/domain/app_event.dart';
import 'package:cookmark/llm/llm_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// T1 #6 실측표의 flash-lite 기본·768px 행.
const _usage = LlmUsage(
  promptTokens: 1157,
  outputTokens: 295,
  thoughtTokens: 0,
  imageTokens: 1064,
  costUsd: 0.00073,
  model: 'gemini-3.1-flash-lite',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('빈 스토리지의 이벤트 로그는 빈 목록이다', () async {
    final storage = await Storage.open();
    expect(storage.readEvents(), isEmpty);
  });

  test('이벤트를 기록한 순서 그대로 읽는다', () async {
    final storage = await Storage.open();
    await storage.appendEvent(
      AppEvent.photoUpload(
        at: DateTime.utc(2026, 7, 15, 19),
        bytes: 100,
        width: 768,
      ),
    );
    await storage.appendEvent(
      AppEvent.recognitionDone(
        at: DateTime.utc(2026, 7, 15, 19, 0, 2),
        latency: const Duration(milliseconds: 1940),
        usage: _usage,
        count: 7,
      ),
    );

    expect(storage.readEvents().map((e) => e.type), [
      AppEventType.photoUpload,
      AppEventType.recognitionDone,
    ]);
  });

  test('새로고침(스토리지 재오픈) 후에도 이벤트가 유지된다', () async {
    final first = await Storage.open();
    await first.appendEvent(
      AppEvent.photoUpload(
        at: DateTime.utc(2026, 7, 15, 19),
        bytes: 100,
        width: 768,
      ),
    );

    // 같은 백엔드를 다시 연다 — 브라우저를 닫았다 여는 것에 해당한다.
    final reopened = await Storage.open();
    expect(reopened.readEvents(), hasLength(1));
    expect(reopened.readEvents().single.type, AppEventType.photoUpload);
  });

  test('인식 완료 이벤트는 지연·토큰·원가를 실어 나른다 — 향후 과금 설계의 바닥 데이터', () async {
    final storage = await Storage.open();
    await storage.appendEvent(
      AppEvent.recognitionDone(
        at: DateTime.utc(2026, 7, 15, 19),
        latency: const Duration(milliseconds: 1940),
        usage: _usage,
        count: 7,
      ),
    );

    final data = storage.readEvents().single.data;
    expect(data['latencyMs'], 1940);
    expect(data['promptTokens'], 1157);
    expect(data['outputTokens'], 295);
    expect(data['thoughtTokens'], 0);
    expect(data['imageTokens'], 1064);
    expect(data['costUsd'], 0.00073);
    expect(data['count'], 7);
  });

  test('타임스탬프는 왕복해도 같은 시각이다 — 업로드 세션이 여기서 파생된다', () async {
    final at = DateTime.utc(2026, 7, 15, 19, 30, 15);
    final storage = await Storage.open();
    await storage.appendEvent(
      AppEvent.photoUpload(at: at, bytes: 1, width: 768),
    );

    final reopened = await Storage.open();
    expect(reopened.readEvents().single.at, at);
  });
}
