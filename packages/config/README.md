# packages/config — 계약

이 디렉토리는 비어 있다. 코드가 아니라 좌표다 (ADR-0008).

- **무엇이 들어오는가.** `@repo/typescript-config` + `@repo/biome-config`(lint+format 단일 도구, `next` 도메인 활성) — TS 툴체인 표준의 실체([#80](https://github.com/woosung-dev/cookmark/issues/80) 확정).
- **어떤 rules가 규율하는가.** #80 해소 결정 — pnpm workspaces 단독(turborepo는 트리거 도입 — TS 앱 2개째 또는 공유 패키지 빌드가 CI 체감 비용화), Node 24 LTS·Next 16 핀, 메이저 업은 명시 결정. ESLint/Prettier 불채택 — Biome 미커버 결함 클래스 실증 시 ESLint 보완 재결정(트립와이어).
- **실체화 트리거.** 첫 TS 앱(apps/admin) 실체화와 함께.
