# Context Notes — #102 api-6 og:image 프록시

자율결정 감사 추적. 결정/근거 1줄씩 append. 티켓 [#102](https://github.com/woosung-dev/cookmark/issues/102) · 스펙 [#96](https://github.com/woosung-dev/cookmark/issues/96) · 이월 원본 그릴링 [#75](https://github.com/woosung-dev/cookmark/issues/75).

## 스코프 경계 (착수 전 확정)

- **URL만 반환, 이미지 바이트 프록시 없음** — `<img>` 표시는 CORS 무관. 핫링크 차단 실증이 바이트 프록시 재결정 트리거(티켓 명시).
- **LLM 아님** — `BaseLLMService` 밖 일반 아웃바운드 fetch. #103 프록시 승계와 무관하게 독립.
- **클라이언트(Flutter) 반영은 범위 밖** — BE 소비 접점(#83, #38 랜딩 후) 몫. `apps/mobile`엔 이미 "백엔드 오면 og:image로 교체" 주석이 있다.
- **파일럿 무접촉(~8/5)** — `apps/mobile`·`vercel.json`·루트 `api/`(.mjs) 무수정.

## 결정 로그

- **GET `/api/v1/og-image?url=`** (POST 아님) — 멱등 조회는 GET, POST는 #103 LLM 프록시 시그니처로 남겨 API 관례(GET=조회·POST=처리)를 세운다. `Annotated[HttpUrl, Query()]`가 OpenAPI `format: uri, maxLength: 2083`을 산출(설치본 실측) — 쓰레기 URL 422 자동.
- **부재 = 200 `{"image_url": null}`** — og:image 없음·비HTML·upstream 에러·연결 실패·타임아웃·리다이렉트 한도·DNS 실패 전부. 클라이언트에겐 전부 "썸네일 없음"으로 동일하고 AC의 "명시적 부재 응답, 500 아님"을 문자 그대로 만족한다.
- **SSRF 차단만 400** — 유일하게 호출자 입력이 정책 위반인 경우. 차단은 패킷 전송 전 공개 IP 대역 사실만으로 판정하므로 내부망 생존 여부 오라클이 아니다. detail은 일반 문구(내부 판정 상세 비노출).
- **응답 필드는 `str | None`(HttpUrl 아님)** — 이상한 upstream og:image 값이 ResponseValidationError 500으로 터지는 것 방지.
- **SSRF 판정식 = `is_global and not is_multicast and not is_reserved` + IPv4-mapped 언랩** — Python 3.13.12 실측: `is_global` 단독은 멀티캐스트(`224.0.0.1` 등)·NAT64(`64:ff9b::/96`)를 통과시킨다. pydantic이 10진 IP(`2130706433`)→`127.0.0.1` 정규화·IDN punycode를 이미 해주고, IPv6 리터럴 host는 **대괄호 포함**으로 오므로 벗겨야 한다(안 벗기면 호스트네임으로 오인→DNS 경로 누수).
- **리다이렉트 수동 추적(≤5)** — `follow_redirects=False` + `resp.has_redirect_location`(301/302/303/307/308만) + `str(resp.next_request.url)`(httpx가 상대 Location 해석). **hop마다 scheme 재검사 필수** — httpx는 `Location: file://`도 next_request로 조립해준다(0.28.1 소스 확인).
- **전체 데드라인 `asyncio.timeout(10)`** — `httpx.Timeout(5)`는 per-op(connect/read 각각)라 slowloris가 워커를 분 단위로 잡는다. 설계 검증에서 나온 가장 큰 구멍.
- **1 MiB 상한은 읽기 중단 + 부분 파싱** — og 메타는 head에 있으니 읽은 만큼 파싱이 정답. `aiter_bytes(chunk_size=64KiB)` — httpx ByteChunker가 재분할하므로 respx 단일 청크 mock에서도 상한 로직이 실제로 돈다(소스 확인). 상한은 압축 해제 후 기준(안전한 방향).
- **파서 = stdlib HTMLParser** — 신규 의존성 0, 잘린/불량 HTML 무예외(3.5부터 strict 제거). `property=`+`name=`(흔한 오기) 허용, `og:image:secure_url`·`twitter:image` 미채택 — 타깃(네이버·티스토리·만개의레시피·유튜브) 전부 표준 og:image. 디코딩은 incremental decoder(청크 경계 멀티바이트) + `charset_encoding or utf-8`(EUC-KR 사이트 존재).
- **상수(타임아웃 5s·상한 1 MiB·리다이렉트 5) — Settings 아님** — 필수 Settings 필드는 export_openapi·CI env·conftest 3곳 플레이스홀더를 강제한다(리포 자체 관례).
- **요청당 AsyncClient** — 다양한 호스트 1회성 fetch라 풀링 무익, lifespan 배선이 PR 최대 diff가 될 뻔. #103이 공유 클라이언트를 도입하면 재고.
- **`UNAUTHORIZED` 상수를 auth/router.py → auth/dependencies.py 이동** — 자기가 내는 401(`get_current_account`)의 자연스러운 집이고, ogimage가 auth 라우터를 import하는 냄새 제거. 계약 무변경.
- **DNS 리바인딩 TOCTOU 의식적 이월** — 가드 resolve ↔ httpx 재-resolve 사이 틈. 완전 방어(IP 고정 커스텀 transport)는 이 범위 밖, guard.py docstring에 명시. 선례: 실험 1·B(PR #20)도 동일 이월.
- **테스트 DNS는 monkeypatch, dependency_overrides 아님** — 전역 `app`에 overrides는 세션 누수 위험 + 내부 구현을 라우트 시그니처로 승격. service가 `guard.resolve_host`를 **모듈 속성 경유**로 불러 patch 타깃을 1곳으로 고정.
- **respx 전용 `pages` fixture** — 모듈 레벨 `respx.get`은 default router라 `idp` fixture 인스턴스와 별개. respx 0.23.1은 다중 활성 router가 fall-through로 공존(소스 확인).
- **무세션+쓰레기URL은 401(422 아님)** — FastAPI는 서브의존성을 쿼리 검증보다 먼저 푼다(소스 확인). 부수 효과: CI schemathesis 퍼징(무세션)이 전부 401로 끊겨 러너에서 실제 아웃바운드 fetch 0건.

## /code-review 반영 (2축 — Standards·Spec, 하드 위반 0)

- **`_ALLOWED_SCHEMES` 중복 제거(Standards·Duplicated Code)** — guard·service 양쪽 정의를 guard의 `ALLOWED_SCHEMES` 단일 정의로 통합. 정책이 두 파일에서 따로 드리프트하는 위험 제거.
- **데드라인 발화 테스트 추가(Spec)** — 기존 타임아웃 테스트는 예외→null 매핑만 증명했다. `_DripStream`(첫 청크 뒤 0.5s 멈춤, og:image는 멈춤 뒤 청크) + 데드라인 0.05s monkeypatch로 `asyncio.timeout`이 스트림을 실제로 끊는 것을 증명 — null이면 끊긴 것(og가 뒤 청크에만 있으므로 타이밍 단언 불필요·결정적).
- **`extract_og_image()` 편의 함수 유지(지적 기각)** — "테스트 전용" 지적이 있었으나 파서 모듈의 정당한 단발 파싱 API고, 제거 시 유닛 12개가 보일러플레이트를 반복한다. 5줄 비용 감수.
- **FE Playwright smoke 짝 미작성** — backend.md 검증 앵커의 짝 정책은 이 리포에 FE Playwright 하네스가 없어 N/A(Flutter·클라이언트 반영은 #83 이후). PR 본문에 명시.
