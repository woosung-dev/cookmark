# #100 api-4 인증 — 카카오·구글 OIDC 세션 + 탈퇴 하드 삭제 — 체크리스트

계획: `~/.claude/plans/100-auth-oidc-session.md`. 티켓 정본은 [#100](https://github.com/woosung-dev/cookmark/issues/100), 결정 정본은 ADR-0009 인증 절([#77](https://github.com/woosung-dev/cookmark/issues/77)) + `.claude/rules/backend.md` §9·§12. (직전 태스크 #97 체크리스트는 전량 완료 — PR #105 머지됨.)

## 구현

- [ ] 브랜치 `feat/100-auth-oidc-session` + 작업 문서(plan·checklist·context-notes)
- [ ] 의존성 — `authlib`·`itsdangerous`(SessionMiddleware) + dev `respx` — `uv sync` 통과
- [ ] RED — IdP mock 하네스 + 관통·세션·로그아웃·탈퇴 테스트 먼저, 실패 확인
- [ ] GREEN — `auth/{models,oidc,repository,service,dependencies,router,schemas,exceptions}.py`
- [ ] config — 카카오·구글 client id/secret · 세션 키 (SecretStr) + `.env.local` 갱신
- [ ] main 배선 — auth 라우터 + `SessionMiddleware` + CORS `allow_credentials=True`
- [ ] Alembic — `target_metadata = SQLModel.metadata` 복원 + accounts·sessions 마이그레이션
- [ ] 인루프 게이트 — `ruff format` · `ruff check` · `mypy src/` · `pytest` 전량 green

## AC 검증

- [ ] IdP mock 관통 — 콜백 → 계정 생성(iss+sub) → 세션 발급 → 쿠키 세팅 (카카오·구글 각각)
- [ ] 같은 iss+sub 재로그인 시 계정 중복 생성 없음
- [ ] 계정 테이블에 이메일·프로필 컬럼이 존재하지 않음
- [ ] 쿠키·Bearer 양쪽으로 현재 계정 조회 성공, 무세션·위조 토큰은 401
- [ ] 로그아웃 직후 같은 토큰 401 (즉시 무효화)
- [ ] 탈퇴 직후 계정·세션 행 0, 같은 토큰 401
- [ ] 실 카카오·구글 로컬 수동 로그인 데모 1회 — **파운더 몫**(IdP 앱 등록 = 콘솔 작업, CI 밖)

## 마무리

- [ ] `/code-review` + 지적 반영
- [ ] 시맨틱 커밋 → push → PR → CI green → 티켓 코멘트
