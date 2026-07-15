// 웹 타깃 — 브라우저가 자기 정체를 밝히는 유일한 곳.
import 'package:web/web.dart' as web;

String currentUserAgent() => web.window.navigator.userAgent;
