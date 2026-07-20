// 이벤트 로그가 남고 새로고침 후에도 유지되는지 — #14 AC의 영속 부분.
import 'dart:convert';

import 'package:cookmark/data/storage.dart';
import 'package:cookmark/domain/app_event.dart';
import 'package:cookmark/domain/ingredient.dart';
import 'package:cookmark/domain/recipe.dart';
import 'package:cookmark/domain/session_state.dart';
import 'package:cookmark/llm/llm_gateway.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:shared_preferences_platform_interface/types.dart';

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

  group('모르는 유형의 이벤트 — 앞선 버전이 썼거나 백업으로 들어온 것', () {
    /// 카탈로그에 없는 유형 1건이 섞인 로그를 디스크에 미리 깔아둔다.
    void seedWithUnknownEvent() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({
            'events': jsonEncode([
              {
                'type': 'photoUpload',
                'at': '2026-07-15T19:00:00.000Z',
                'bytes': 100,
                'width': 768,
              },
              {'type': '앞선버전이벤트', 'at': '2026-07-15T19:01:00.000Z'},
            ]),
          });
    }

    test('로그 전체를 막지 않는다 — 읽기도 쓰기도 된다', () async {
      seedWithUnknownEvent();
      final storage = await Storage.open();

      // 못 읽는 1건만 빠지고 나머지는 살아 있다.
      expect(storage.readEvents().map((e) => e.type), [
        AppEventType.photoUpload,
      ]);

      // readEvents가 appendEvent를 떠받치므로, 읽기가 터지면 쓰기까지 전부 막힌다.
      await storage.appendEvent(
        AppEvent.photoUpload(
          at: DateTime.utc(2026, 7, 15, 20),
          bytes: 1,
          width: 768,
        ),
      );
      expect(storage.readEvents(), hasLength(2));
    });

    test('지워지지 않는다 — 로그는 덧붙이기만 한다', () async {
      seedWithUnknownEvent();
      final storage = await Storage.open();
      await storage.appendEvent(
        AppEvent.photoUpload(
          at: DateTime.utc(2026, 7, 15, 20),
          bytes: 1,
          width: 768,
        ),
      );

      // 이 빌드가 못 읽는 행이라도 디스크의 원본은 남아야 한다 — 읽을 줄 아는 빌드가 내보낸다.
      final stored =
          (await SharedPreferencesAsyncPlatform.instance!.getPreferences(
                const GetPreferencesParameters(
                  filter: PreferencesFilters(allowList: {'events'}),
                ),
                const SharedPreferencesOptions(),
              ))['events']!
              as String;
      expect(
        [
          for (final e in jsonDecode(stored) as List<Object?>)
            (e! as Map)['type'],
        ],
        ['photoUpload', '앞선버전이벤트', 'photoUpload'],
      );
    });
  });

  group('손상·스키마 드리프트 강등 — localStorage는 배포를 가로질러 산다', () {
    /// 지정한 키에 원시 문자열을 미리 깔아둔다 — 앞선 배포가 남긴 손상 데이터를 흉내낸다.
    void seedRaw(Map<String, String> data) {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(data);
    }

    group('readRecipes', () {
      test('손상 JSON 문자열이면 크래시 없이 빈 목록이다', () async {
        seedRaw({'recipes': '{깨진 json'});
        final storage = await Storage.open();
        expect(storage.readRecipes(), isEmpty);
      });

      test('List가 아니면(객체) 크래시 없이 빈 목록이다', () async {
        seedRaw({
          'recipes': jsonEncode({'url': 'https://a', 'title': 'a'}),
        });
        final storage = await Storage.open();
        expect(storage.readRecipes(), isEmpty);
      });

      test('항목이 Map이 아니면 그 항목만 빠진다', () async {
        seedRaw({
          'recipes': jsonEncode([
            'https://그냥문자열',
            {'url': 'https://a', 'title': '김치찌개'},
          ]),
        });
        final storage = await Storage.open();
        expect(storage.readRecipes().map((r) => r.title), ['김치찌개']);
      });

      test('필수 필드(url) 결손 항목이 섞이면 파싱 가능한 것만 살린다', () async {
        seedRaw({
          'recipes': jsonEncode([
            {'title': 'url 없는 항목'},
            {'url': 'https://a', 'title': '김치찌개'},
            {'url': 'https://b', 'title': '된장찌개'},
          ]),
        });
        final storage = await Storage.open();
        expect(storage.readRecipes().map((r) => r.title), ['김치찌개', '된장찌개']);
      });

      test('정상 데이터는 그대로 읽힌다 — 강등이 회귀를 만들지 않는다', () async {
        final storage = await Storage.open();
        await storage.writeRecipes([
          const Recipe(
            url: 'https://a',
            title: '김치찌개',
            ingredients: ['김치', '돼지고기'],
          ),
        ]);
        final read = storage.readRecipes().single;
        expect(read.url, 'https://a');
        expect(read.title, '김치찌개');
        expect(read.ingredients, ['김치', '돼지고기']);
      });
    });

    group('readSession', () {
      test('손상 JSON이면 크래시 없이 null이다 — 세션 없음으로 부팅한다', () async {
        seedRaw({'session': '{깨진 json'});
        final storage = await Storage.open();
        expect(storage.readSession(), isNull);
      });

      test('필드 결손이면 크래시 없이 null이다', () async {
        seedRaw({
          'session': jsonEncode({'다른필드': 1}),
        });
        final storage = await Storage.open();
        expect(storage.readSession(), isNull);
      });

      test('정상 세션은 그대로 읽힌다 — 강등이 회귀를 만들지 않는다', () async {
        final storage = await Storage.open();
        await storage.writeSession(
          const SessionState(
            ingredients: [
              Ingredient(
                name: '김치',
                confidence: Confidence.high,
                checked: true,
              ),
            ],
          ),
        );
        final read = storage.readSession()!;
        expect(read.ingredients.single.name, '김치');
        expect(read.ingredients.single.checked, isTrue);
      });
    });

    group('readEvents', () {
      test('top-level이 손상 JSON이면 크래시 없이 빈 목록이다', () async {
        seedRaw({'events': '[깨진 json'});
        final storage = await Storage.open();
        expect(storage.readEvents(), isEmpty);
      });

      test('항목이 손상(필드 결손)이면 그 항목만 빠진다', () async {
        seedRaw({
          'events': jsonEncode([
            {'type': 'photoUpload'}, // at 결손 — parse가 throw하는 모양.
            {
              'type': 'photoUpload',
              'at': '2026-07-15T19:00:00.000Z',
              'bytes': 100,
              'width': 768,
            },
          ]),
        });
        final storage = await Storage.open();
        expect(storage.readEvents().map((e) => e.type), [
          AppEventType.photoUpload,
        ]);
      });
    });

    // 하드닝은 읽기만이 아니라 쓰기(appendEvent)도 막지 않아야 한다 — 손상 blob에 첫
    // photoUpload를 append하다 throw하면 인식이 영원히 시작 안 되고 코어 루프가 죽는다.
    group('appendEvent (손상 blob에도 쓰기가 막히지 않는다)', () {
      test('events가 손상 JSON이어도 append가 throw하지 않고 새 로그로 이어간다', () async {
        seedRaw({'events': '{깨진 json'});
        final storage = await Storage.open();
        await storage.appendEvent(
          AppEvent.photoUpload(
            at: DateTime.utc(2026, 7, 20),
            bytes: 1,
            width: 1,
          ),
        );
        expect(storage.readEvents().map((e) => e.type), [
          AppEventType.photoUpload,
        ]);
      });

      test('events가 List가 아니어도(객체) append가 새 로그로 시작한다', () async {
        seedRaw({
          'events': jsonEncode({'not': 'a list'}),
        });
        final storage = await Storage.open();
        await storage.appendEvent(
          AppEvent.photoUpload(
            at: DateTime.utc(2026, 7, 20),
            bytes: 1,
            width: 1,
          ),
        );
        expect(storage.readEvents(), hasLength(1));
      });

      test('정상 blob이면 기존 항목 뒤에 이어 붙인다 — 강등이 회귀를 만들지 않는다', () async {
        final storage = await Storage.open();
        await storage.appendEvent(
          AppEvent.photoUpload(
            at: DateTime.utc(2026, 7, 15),
            bytes: 1,
            width: 1,
          ),
        );
        await storage.appendEvent(
          AppEvent.photoUpload(
            at: DateTime.utc(2026, 7, 16),
            bytes: 1,
            width: 1,
          ),
        );
        expect(storage.readEvents(), hasLength(2));
      });
    });
  });

  group('기록 초기화 — 보존 경계는 "레시피 빼고 다" (#144)', () {
    /// 5개 키 전부에 값을 채운다 — 초기화가 무엇을 지우고 무엇을 남기는지 재려면
    /// 시작 상태에 그 다섯이 **모두** 있어야 한다. 하나라도 비면 그 키의 단언이 공허해진다.
    Future<Storage> seedEveryKey() async {
      final storage = await Storage.open();
      await storage.appendEvent(
        AppEvent.photoUpload(
          at: DateTime.utc(2026, 7, 20),
          bytes: 100,
          width: 768,
        ),
      );
      await storage.writeSession(
        const SessionState(ingredients: [Ingredient.added('대파')]),
      );
      await storage.writeRecipes([
        const Recipe(
          url: 'https://youtu.be/abc',
          title: '김치찌개',
          ingredients: ['김치', '돼지고기'],
        ),
      ]);
      await storage.writeLastBackupAt(DateTime.utc(2026, 7, 19));
      await storage.markExpectationNoteSeen();
      return storage;
    }

    /// 디스크에 실제로 남아 있는 키 — 공개 게터가 아니라 영속층을 직접 본다.
    ///
    /// 게터로만 재면 "null을 돌려주니 지워졌다"까지만 알 수 있는데, 그건 빈 값을 써넣은
    /// 경우와 구별되지 않는다. 티켓이 요구하는 "키 단위" 고정은 이 층에서만 성립한다.
    Future<Set<String>> storedKeys() async =>
        (await SharedPreferencesAsyncPlatform.instance!.getPreferences(
          const GetPreferencesParameters(filter: PreferencesFilters()),
          const SharedPreferencesOptions(),
        )).keys.toSet();

    test('레시피 키만 남고 나머지 4개는 사라진다', () async {
      final storage = await seedEveryKey();
      expect(await storedKeys(), {
        'events',
        'session',
        'recipes',
        'lastBackupAt',
        'expectationNoteSeen',
      }, reason: '초기화 전에 5개 키가 다 있어야 이 테스트가 공허하지 않다');

      await storage.clearPilotRecord();

      // 여기가 문서가 약속하는 "레시피 빼고 다"의 기계적 정본이다. 키가 추가되면
      // 이 단언이 깨지고, 다음 세션은 그 키를 어느 쪽에 둘지 **결정하도록 강제된다**.
      expect(await storedKeys(), {'recipes'});
    });

    test('레시피는 내용까지 그대로다 — 지우고 되살리는 게 아니다', () async {
      final storage = await seedEveryKey();
      await storage.clearPilotRecord();

      final recipes = storage.readRecipes();
      expect(recipes, hasLength(1));
      expect(recipes.single.url, 'https://youtu.be/abc');
      expect(recipes.single.title, '김치찌개');
      expect(recipes.single.ingredients, ['김치', '돼지고기']);
    });

    test('초기화 후 읽기는 갓 설치한 기기와 같다 — 이벤트 0이 정상이다', () async {
      final storage = await seedEveryKey();
      await storage.clearPilotRecord();

      // 웹에서는 재import가 backup/import 1건을 남겨 "이벤트 1"이 정상이었다.
      // 네이티브는 재import 자체가 사라져 0이 정상이다(#41 불변식 반전).
      expect(storage.readEvents(), isEmpty);
      expect(storage.readSession(), isNull);
      expect(storage.readLastBackupAt(), isNull);
      expect(storage.readExpectationNoteSeen(), isFalse);
    });

    test('다시 열어도 지워진 채다 — 캐시만 비운 게 아니다', () async {
      final storage = await seedEveryKey();
      await storage.clearPilotRecord();

      final reopened = await Storage.open();
      expect(reopened.readEvents(), isEmpty);
      expect(reopened.readSession(), isNull);
      expect(reopened.readRecipes(), hasLength(1));
    });

    test('빈 스토리지에서 초기화해도 터지지 않는다 — 두 번 눌러도 같다', () async {
      final storage = await Storage.open();
      await storage.clearPilotRecord();
      await storage.clearPilotRecord();

      expect(storage.readEvents(), isEmpty);
      expect(await storedKeys(), isEmpty);
    });
  });
}
