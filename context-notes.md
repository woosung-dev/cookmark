# Context Notes — #100 api-4 인증 (카카오·구글 OIDC 세션 + 탈퇴 하드 삭제)

자율결정 감사 추적. 결정/근거 1줄씩 append. 계획: `~/.claude/plans/100-auth-oidc-session.md`.

## 스코프 경계 (착수 전 확정)

- **#100 = 인증 수직 슬라이스만.** 레시피 북 CRUD·스코프드 Repository는 #103, LLM 승계는 #101, 배포·Secret Manager는 #98, OpenAPI 스냅샷·드리프트 가드는 #99 — 이 PR에 넣지 않는다.
- 루트 `api/`(.mjs 프록시)·`vercel.json`·`apps/mobile` 무접촉 (파일럿 가드 ~8/5).
- 병렬 worktree 있음(#98·#99) — 공유 파일(`conftest.py`·`main.py`·`config.py`) 편집은 최소 표면으로.

## 결정 로그 (착수 전)

- **세션 토큰은 DB에 SHA-256 해시로만 보관** — 원문 보관 시 DB·백업 유출이 곧 세션 탈취다. ADR-0009가 PITR 백업 잔존을 명시적으로 인정하므로(§12.3), 그 잔존물이 살아있는 세션이면 안 된다. 표면 +3줄. 티켓은 "불투명 세션 ID"만 요구하고 해시를 요구하진 않았다 — 자율 판단.
- **`expires_at` 포함, TTL 30일 모듈 상수** — 쿠키 `Max-Age`의 서버측 짝이 없으면 토큰이 영구 유효해진다(쿠키만 만료되고 Bearer로는 계속 통과). 설정 노브는 안 만든다(요구 없음). 만료 행 청소 잡은 범위 밖 — 트리거 = 행 증가가 실문제화.
- **계정 중복 방지 = UNIQUE(iss, sub) DB 제약** — "조회 후 없으면 생성" 관례가 아니라 구조로 막는다(§12.2의 정신).
- **`SessionMiddleware`는 우리 인증 세션이 아니다** — authlib의 OAuth state·nonce 운반 전용(itsdangerous 서명 쿠키, 수명 5분). ADR-0009 비밀 5개 중 "세션 서명/암호화 키"의 소비처가 정확히 여기다. 우리 세션은 DB 테이블이고 불투명 ID다(§9).
- **콜백 응답 = 쿠키 + JSON(토큰 포함)** — 리다이렉트 대상은 소비할 FE가 1기에 없어(스펙 Out of Scope: `apps/mobile` 무변경) 설정 선지불이다. 토큰을 본문에 넣는 근거는 #77 "같은 불투명 토큰을 네이티브가 Bearer로" — 본문 말고는 비-브라우저 클라이언트가 토큰을 얻을 경로가 없다. **트리거 = FE 소비 시 리다이렉트 재결정.**
- **`redirect_uri` = `request.url_for`** — 설정 0으로 로컬 데모가 성립한다. Cloud Run HTTPS 프록시 헤더(`--forwarded-allow-ips`) 배선은 #98의 몫이며, 그때 x-forwarded-proto가 없으면 http URL이 나가 IdP 등록값과 어긋난다는 것이 인수인계 사항.
- **provider 자격증명은 필수 필드(placeholder 아님)** — 없으면 부팅 실패가 조용한 로그인 장애보다 낫다. `.env.local`(gitignored)에 로컬 값, 배포는 Secret Manager(#98).

## 구현 중 발견·결정 (append)
