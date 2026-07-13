# 코딩 스탠다드

MVP(질문 검증기) 코드 작성 규약. 2026-07-13 문답으로 확정.

## 스택

- Next.js(App Router) + TypeScript(strict), Vercel 배포.
- 로그인·서버 DB 없음 — localStorage가 유일한 영속층.

## 도구

- **Biome** — 린트 + 포맷 단일 도구. ESLint/Prettier 도입 금지.
- **Vitest** — 순수 로직 유닛 테스트.
- **Playwright** — E2E. 검증의 정본은 E2E이고, 유닛은 보완이다.

## 상태·경계

- 상태 관리는 React 내장 훅(useState/useReducer/Context)만. 외부 상태 라이브러리(Zustand·Redux 등) 금지.
- localStorage 접근은 단일 스토리지 모듈을 통해서만 — 컴포넌트에서 `window.localStorage` 직접 호출 금지. 이벤트 로그·레시피 북의 읽기/쓰기 경계를 한 곳에 모은다.
- LLM 호출(인식·매칭)은 단일 경계 모듈을 통해서만 — 테스트 페이크 주입 지점이자 유일한 seam. 모델명은 환경변수 주입.

## 테스트

- 외부 행동만 검증한다 — 브라우저에서 보이는 것과 export JSON에 남는 것. 내부 구현 세부에 비의존.
- E2E는 LLM 경계에 결정적 페이크를 주입해 돌린다.

## 네이밍·문서

- 도메인 개념의 이름은 루트 `CONTEXT.md` 글로서리를 따른다 — `_Avoid_` 동의어로 표류 금지.
- 새 소스 파일 첫 줄에 역할을 설명하는 한국어 주석 1줄(설정 파일 제외).
