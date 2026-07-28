// 기기 세션 경계 — 익명 등록 토큰을 얻고, 두 서버 경계에 실어 보내고, 401이면 재등록한다(#168).
import 'package:http/http.dart' as http;

/// 익명 기기 세션의 경계. 구현은 실 HTTP(운영)와 페이크(테스트) 둘뿐이다.
///
/// 책임은 셋이고 그 셋이 이 seam의 정의다(스펙 #161 §D) — ① 저장된 토큰이 없으면 등록한다
/// ② 토큰을 LLM 경계와 서버 레시피 북 경계에 공급한다 ③ 401을 만나면 재등록한다.
/// ②·③의 정책은 [sendWithDeviceSession] 한 곳에 산다.
///
/// **로그인 화면·탭·설정 항목은 만들지 않는다**(ADR-0012) — 등록은 부팅 경로에서 일어나고
/// 사용자에게 보이지 않는다. 그래서 이 경계는 UI를 모른다.
abstract interface class DeviceSession {
  /// 지금 쓸 토큰. 저장된 것이 없으면 **등록해서** 만든다(책임 ①).
  ///
  /// 발급 응답의 `expires_at`은 읽지 않는다 — 서버의 슬라이딩 갱신이 그 값을 계속 뒤로 밀어
  /// 발급 시점 값이 첫 요청 이후 낡는다. 만료의 신호는 **401 하나뿐**이다(ADR-0012).
  Future<String> token();

  /// 401을 받았을 때 — 새 계정을 받아 토큰을 갈아끼운다(책임 ③).
  ///
  /// [usedToken]은 **401을 받은 그 토큰**이다. 다른 경계가 이미 갈아끼웠다면 등록하지 않고
  /// 새 토큰을 그대로 준다 — 두 경계가 같은 죽은 토큰으로 각자 401을 받았을 때 계정이 둘 나고
  /// 하나가 즉시 고아가 되는 것을 막는다(고아 파기는 파운더 수동이다, ADR-0012).
  Future<String> reregister(String usedToken);
}

/// 기기 세션 경계가 밖으로 내보내는 유일한 실패.
///
/// 등록 거부(403)·네트워크·타임아웃·응답 형식 불일치를 한 값으로 뭉친다. **앱이 이 넷에 대해
/// 할 수 있는 일이 같기 때문이다** — 등록 키는 빌드 자격증명이라 재시도로 고쳐지지 않고(#167이
/// 거부를 401이 아니라 403으로 낸 이유), 나머지 셋은 이미 서버 도달 실패다. 갈라야 할 이유가
/// 생기면 그때 갈린다(`mobile.md` §8 사전 확장 금지).
class DeviceSessionFailure implements Exception {
  const DeviceSessionFailure([this.detail]);

  final String? detail;

  @override
  String toString() =>
      detail == null ? 'DeviceSessionFailure' : 'DeviceSessionFailure($detail)';
}

/// 경계 밖으로 정규화되지 않은 실패가 새지 않게 한다 — LLM 경계의 `normalizeLlmFailures`와 동형.
///
/// 200인데 모양이 다른 본문이 던지는 것은 `Exception`이 아니라 `TypeError`(= `Error`)라
/// `on Exception`으로는 못 잡는다. 그 차이가 폐기된 arm #25를 죽인 결함의 전부였다(#142).
Future<T> normalizeDeviceSessionFailures<T>(
  Future<T> Function() interpret,
) async {
  try {
    return await interpret();
  } on DeviceSessionFailure {
    // 이미 정규화된 실패다 — 다시 감싸면 detail이 중첩된다.
    rethrow;
  } catch (e) {
    // bare catch는 Error까지 잡는다 — on Exception이 못 잡는 그 차이가 요점이다.
    throw DeviceSessionFailure('응답 형식 불일치: $e');
  }
}

/// 세션 토큰을 실어 보내고, 401이면 재등록 후 **딱 한 번만** 다시 보낸다(책임 ②·③).
///
/// 정책이 여기 한 곳에만 사는 이유 — 401은 두 서버 경계(LLM · 레시피 북) 어디서든 오는데,
/// 각자 처리하면 "몇 번 재시도하는가"가 두 곳에서 갈린다. 재전송을 1회로 못박은 것도 같은
/// 이유다: 등록 직후 토큰이 또 401이면 그건 세션 만료가 아니라 서버 쪽 사건이고, 무한 재등록은
/// 화면에 아무것도 안 보인 채 도는 부팅 루프가 된다(#167이 거부 코드로 403을 고른 것과 같은 판단).
///
/// **401을 여기서 흡수하므로 두 경계의 실패 택소노미는 무변경이다** — `LlmFailureKind`에 신규
/// 값이 생기지 않는다. 재등록마저 실패하면 [DeviceSessionFailure]가 올라가고 각 경계가 자기
/// 정규화로 접는다(#166 실패 문구가 그대로 맞는다 — 그건 서버 도달 실패이지 사용자 입력 실패가
/// 아니다).
Future<http.Response> sendWithDeviceSession(
  DeviceSession session,
  Future<http.Response> Function(String token) send,
) async {
  final used = await session.token();
  final response = await send(used);
  if (response.statusCode != 401) return response;
  return send(await session.reregister(used));
}
