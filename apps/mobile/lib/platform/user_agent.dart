// 브라우저 user agent를 읽는 경계 — 웹에만 있는 API라 플랫폼별로 갈라둔다(ADR-0005: Android는 후순위 타깃).
export 'user_agent_stub.dart'
    if (dart.library.js_interop) 'user_agent_web.dart';
