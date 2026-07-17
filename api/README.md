# api/ — 서버리스 LLM 프록시 (루트 잠정)

지금 돌아가는 프록시 3개(`recognize.mjs`·`extract.mjs`·`match.mjs`)와 공용 헬퍼(`_gemini.mjs`). Vercel 파일 관례가 배포 루트의 `api/`를 요구해 여기 산다 (ADR-0008).

- **규율.** ADR-0005 — 앱과 분리된 서버리스 함수, API 키는 절대 클라이언트에 두지 않는다. 라우팅은 `vercel.json` rewrites가 참조한다.
- **승계.** `apps/api` 실체화 ADR(미래 wayfinder 지도 산출)이 승계·폐지를 결정할 때까지 이동 금지.
