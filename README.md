# cookmark (냉파)

냉장고 사진 1장으로 재고를 파악하고, 저장 레시피와 맞춰 "오늘 뭐 해먹지"를 끝내는 **질문 검증기**.
완성 제품이 아니라 두 질문에 답하기 위한 증거 수집 장치다 — 자세한 건 `CONTEXT.md`와 스펙 #13.

Flutter 단일 코드베이스, 파일럿 배포 타깃은 **Web 빌드**(ADR-0005).

## 개발

```bash
flutter pub get
flutter run -d chrome        # 앱 실행 (인식은 /api/recognize 프록시 필요)
```

## 검증

```bash
flutter analyze              # 린트
flutter test                 # 유닛 — 순수 로직 보완
./scripts/e2e.sh             # E2E(Web 타깃) — 검증의 정본
```

E2E는 chromedriver가 필요하다 (`brew install --cask chromedriver`).
LLM 경계에 결정적 페이크를 주입하므로 API 키 없이 돈다.

## LLM 프록시

`api/recognize.mjs` — 서버리스 함수(Vercel). API 키는 여기에만 있고 클라이언트엔 없다.

| 환경변수 | 뜻 | 기본값 |
|---|---|---|
| `GEMINI_API_KEY` | Gemini API 키 (필수) | — |
| `GEMINI_MODEL` | 인식 모델 | `gemini-3.1-flash-lite` |

## 문서

- `CONTEXT.md` — 도메인 글로서리(용어의 정본)
- `DESIGN.md` — 디자인 언어(색·타이포·간격). 화면 구조의 정본은 아니다 — 그건 ADR-0001.
- `docs/adr/` — 결정 기록. 0001 단일 페이지 · 0003 수동 수정 산식(파일럿 중 불변) · 0005 Flutter
- `docs/coding-standards.md` — 코드 규약
- `docs/tickets/` — 티켓별 체크리스트·컨텍스트 노트
