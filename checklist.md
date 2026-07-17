# #100 api-4 인증 — 카카오·구글 OIDC 세션 + 탈퇴 하드 삭제 — 체크리스트

계획: `~/.claude/plans/100-auth-oidc-session.md`. 티켓 정본은 [#100](https://github.com/woosung-dev/cookmark/issues/100), 결정 정본은 ADR-0009 인증 절([#77](https://github.com/woosung-dev/cookmark/issues/77)) + `.claude/rules/backend.md` §9·§12. (직전 태스크 #97 체크리스트는 전량 완료 — PR #105 머지됨.)

## 구현

- [x] 브랜치 `feat/100-auth-oidc-session` + 작업 문서(plan·checklist·context-notes)
- [x] 의존성 — `authlib` 1.7.2·`itsdangerous`(SessionMiddleware) + dev `respx` — `uv sync` 통과
- [x] RED — IdP mock 하네스 + 관통·세션·로그아웃·탈퇴 테스트 먼저
- [x] GREEN — `auth/{models,oidc,repository,service,dependencies,router,schemas,exceptions}.py`
- [x] config — 카카오·구글 client id/secret · 세션 키 (SecretStr) + `.env.local` 갱신
- [x] main 배선 — auth 라우터 + `SessionMiddleware` + CORS `allow_credentials=True`(+ 와일드카드 거부)
- [x] Alembic — `target_metadata = SQLModel.metadata` 복원 + accounts·sessions 마이그레이션
- [x] 인루프 게이트 — `ruff format` · `ruff check` · `mypy src/` · `pytest` 전량 green (29 passed)

## AC 검증

- [x] IdP mock 관통 — 콜백 → 계정 생성(iss+sub) → 세션 발급 → 쿠키 세팅 (카카오·구글 각각) — `test_callback_creates_account_and_issues_session[kakao|google]` · `test_callback_sets_httponly_secure_lax_cookie[kakao|google]`
- [x] 같은 iss+sub 재로그인 시 계정 중복 생성 없음 — `test_relogin_with_same_identity_reuses_account` + UNIQUE(iss, sub) 제약
- [x] 계정 테이블에 이메일·프로필 컬럼이 존재하지 않음 — `test_accounts_table_has_no_email_or_profile_columns`가 실 DB `information_schema`에서 `{id, iss, sub, created_at}` 정확 일치 확인(모델 코드가 아니라 실 스키마)
- [x] 쿠키·Bearer 양쪽으로 현재 계정 조회 성공, 무세션·위조 토큰은 401 — `test_me_with_cookie` · `test_me_with_bearer` · `test_me_without_session_is_401` · `test_me_with_forged_token_is_401`
- [x] 로그아웃 직후 같은 토큰 401 — `test_logout_kills_the_token_immediately`(401 + 실 DB 세션 행 0 = 삭제이지 만료 표시 아님)
- [x] 탈퇴 직후 계정·세션 행 0, 같은 토큰 401 — `test_withdraw_hard_deletes_account_and_sessions`(실 Postgres FK CASCADE `confdeltype='c'`)
- [ ] **실 카카오·구글 로컬 수동 로그인 데모 1회 — 파운더 몫**(IdP 앱 등록 = 콘솔 작업, CI 밖). 절차는 `apps/api/README.md`「실 IdP 로컬 로그인 데모」. 코드측 준비는 끝 — 실 discovery 왕복으로 두 provider의 authorize 리다이렉트(302, `scope=openid`+state+nonce)까지 로컬 확인했다.

### 추가 확인 (AC 밖·자발)

- [x] ID 토큰 검증이 실제로 돈다 — `test_login_rejects_id_token_signed_by_impostor`(IdP 아닌 키 서명 → 401·계정 0) + SCOPE에서 `openid`를 빼는 뮤테이션으로 로그인 테스트 7건 실패(= authlib fail-open 함정에 fail-closed)
- [x] 세션 토큰 원문이 DB에 없다 — `test_session_token_is_not_stored_in_plaintext`
- [x] 만료 세션 401 — `test_expired_session_is_401`
- [x] 마이그레이션 드리프트 가드 — `test_migrations_match_models`(모델에 컬럼 추가하는 뮤테이션으로 실패 확인)
- [x] CI 조건 재현 — `.env.local` 치우고 전체 스위트 green(#99 세션이 남긴 "로컬 green을 가린다" 함정 교차 확인)

## 마무리

- [x] `/code-review` + 지적 반영 — Standards 하드 위반 0 · Spec 실결함 1건(드리프트 가드가 전체 스위트에서 항상 실패) 수정, `type: ignore` 3건 제거 (6793800)
- [x] push → PR [#107](https://github.com/woosung-dev/cookmark/issues/107) → CI green(run 29584277588, `29 passed in 8.18s` — 러너 testcontainers 실구동) → 티켓 코멘트
