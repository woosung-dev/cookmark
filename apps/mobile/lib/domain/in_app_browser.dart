// 카톡 인앱 브라우저 감지 — 여기서 쓰면 localStorage가 유실된다(#21, ADR-0005 웹 전제).
//
// 파일럿 온보딩이 카톡 URL 공유(G2 #9 규약)라 링크를 그냥 누르면 인앱 브라우저로 열린다.
// 그 안의 스토리지는 앱이 정리할 때 같이 날아갈 수 있고, 그러면 2주 데이터가 사라진다.

/// 카톡 인앱 브라우저의 user agent 표식.
///
/// 카톡만 본다 — 파일럿의 유일한 배포 경로가 카톡 URL 공유이기 때문이다(G2 #9).
/// 다른 앱의 인앱 브라우저는 스펙 밖이다.
const _kakaoMarker = 'KAKAOTALK';

bool isKakaoInAppBrowser(String userAgent) =>
    userAgent.toUpperCase().contains(_kakaoMarker);
