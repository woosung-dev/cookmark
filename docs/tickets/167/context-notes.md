# #167 결정 로그 — 익명 기기 등록 · 슬라이딩 세션 · 배포 시크릿

체크리스트는 `checklist.md`. 여기엔 **왜 그렇게 골랐는가**와 **실측으로 닫은 것**만 남긴다.

## 파운더가 이 세션에 확정한 계약 3건

### ① 등록 키 운반 = `Authorization: Bearer <키>`

셋을 놓고 골랐다 — 전용 헤더(`X-Cookmark-Register-Key`) · 요청 본문 필드 · `Authorization` 재사용. **파운더가 셋째를 택했다.** 새 헤더 이름이 안 생기고 Dart 쪽 구현이 기존 Bearer 배선을 그대로 쓴다.

**이 선택의 유일한 실물 위험은 쿠키 폴백이었다.** `extract_session_token`(`src/auth/dependencies.py`)은 헤더가 없으면 **쿠키로 떨어진다** — 등록이 그 함수를 재사용했다면 남아 있던 세션 쿠키가 등록 키로 읽혔을 것이다. 그래서 등록은 `_bearer_value`(헤더만 본다)로 **추출을 갈랐고**, `test_register_key_does_not_fall_back_to_the_session_cookie`가 그 성질을 잠근다.

두 함수를 합치지 않은 것도 결정이다 — `extract_session_token`은 **빈 Bearer도 명시로 취급해 쿠키로 안 떨어지고**, `_bearer_value`는 빈 Bearer를 부재로 접는다. 합치는 리팩터를 한 번 했다가 그 차이가 조용히 사라지는 걸 보고 되돌렸다. 주석으로 못박아 뒀다.

### ② 거부 코드 = 403

**401이면 앱이 무한 루프한다.** 스펙 #161이 기기 세션 경계의 책임 ③을 *"401을 만나면 재등록한다"* 로 정의했는데, 등록 자체가 401을 내면 재등록 → 401 → 재등록이 부팅 경로에서 **화면에 아무것도 안 보인 채** 돈다. 403이면 그 혼동이 구조적으로 불가능하다. 의미도 403이 맞다 — 등록 키는 사용자 자격증명이 아니라 **빌드 자격증명**이고, 회전이 곧 APK 재배포라 클라이언트가 재시도로 고칠 수 있는 게 없다.

**없음과 틀림을 바이트 동일한 403**으로 낸다 — 공개 URL에서 어느 쪽인지 알려줄 이유가 없다(부재와 남의 것을 같은 404로 내는 recipes 관용구와 동형).

### ③ 등록 응답에 세션 쿠키를 붙이지 않는다

로그인 콜백은 붙인다. **대칭을 깨는 쪽을 택했다** — ADR-0012가 선언한 소비자는 네이티브 Bearer 하나뿐이고, 요청되지 않은 운반을 만들지 않는다(`mobile.md` §8 사전 확장 금지와 같은 취지). 부수 이득 — 공유 쿠키 jar를 쓰는 소비자에서 계정이 조용히 섞이는 사고(기존 `login_bearer`가 `cookies.clear()`로 막고 있는 바로 그것)를 애초에 안 만든다.

## 실측으로 닫은 위험 3건 (추측하지 않았다)

1. **의존성 단계의 중간 커밋.** 슬라이딩이 요청 스코프 `AsyncSession`을 라우트 본문 **전에** 커밋한다. 하류 레포지토리의 트랜잭션 기대를 깨는지가 최대 리스크였다 — **전량 green**(253)으로 닫았다. 특히 bulk import의 전무-전유 원자성(`test_recipes_import`)과 502 미저장(`test_recipes_crud`)이 살아 있다. 커밋 시점이 그 트랜잭션들 **앞**이라 무관한 구조다.
2. **schemathesis가 새 403을 어떻게 보는가.** v4의 `positive_data_acceptance`가 스키마상 유효한 요청의 4xx를 결함으로 볼 여지가 있었다. 자리표시자 DB로 실 서버를 띄워 국소 재현 → **1937 케이스 전량 pass.** `--exclude-path-regex`를 넓힐 필요가 없다. (기존 무세션 401 라우트들이 이미 통과 중이었던 것과 같은 이유다.)
3. **`Field(validation_alias=...)`가 pydantic-settings에서 도는가.** `test_config.py`가 즉시 판정했다 — env 이름은 alias로 대소문자 무시 조회되고 `Settings(_env_file=None)` 경로도 무손상. **부작용 하나** — alias를 달면 필드명(`REGISTER_KEY`)으로는 더 이상 안 읽힌다(`populate_by_name` 미설정). 지금 리포에 그렇게 읽는 곳이 없어 감수하고, 선지불로 켜지 않았다.

## 함정 — 코드리뷰가 아니라 설계 리뷰가 잡은 것

**`secrets.compare_digest`는 비-ASCII `str`에 `TypeError`를 던진다.** Starlette은 헤더를 latin-1로 디코드하므로 0x80 이상 바이트가 **비-ASCII str로 도착**한다 — `str`끼리 비교하면 403이어야 할 요청이 **500**이 된다. 그리고 그런 요청을 보내는 게 정확히 이 티켓의 위협 모델("URL을 찍어보는 스캐너")이다.

인터프리터로 직접 확인했고(`TypeError: comparing strings with non-ASCII characters is not supported`), `.encode()` 후 bytes로 비교한다. 회귀 가드는 `test_non_ascii_register_key_is_refused_not_crashed` — **httpx가 헤더 값을 기본 ascii로 인코딩**해서 문자열로는 재현이 안 된다. 바이트 튜플 목록으로 실어야 한다:

```python
await client.post(DEVICE, headers=[(b"authorization", b"Bearer \xff\xfe\x80")])
```

## 고른 것과 안 고른 것 (구현 세부)

- **`register_device()`는 `login()`을 재사용한다** — uuid4라 계정 재사용 분기를 절대 안 타므로 SELECT 한 번이 낭비다. 그 한 번을 아끼려 세션 발급 경로를 복제하는 쪽이 훨씬 비싸다. 낭비라는 사실을 docstring에 적었다.
- **`extend_expiry`의 WHERE에 `expires_at > now`를 들려 보냈다** — 호출 순서(조회 성공 뒤에만 부른다)만으로도 죽은 세션은 안 되살아나지만, **문장 하나만 봐도** 그게 참이면 다음 사람이 순서를 바꿔도 안전하다.
- **갱신 실패를 삼키지 않는다** — try/except로 감싸면 읽기 라우트가 조용히 갱신 없이 성공하는 숨은 모드가 생긴다. UPDATE를 못 받는 DB는 어차피 잠시 뒤 라우트를 죽인다. "삼켜라"는 리뷰에서 나올 법한 제안이라 답을 코드에 선적재해 뒀다.
- **`expire_on_commit=False`가 편의에서 정합성 요건으로 승격됐다** — 중간 커밋 뒤 라우트 본문이 `account.id`를 만지므로, True로 뒤집으면 greenlet 밖 lazy refresh로 죽는다. `common/database.py`에 한 줄로 못박았다.
- **한 문장 CTE(`UPDATE ... RETURNING` + accounts 조인)로 왕복을 안 늘리는 길**이 있다. 안 만들었다 — 측정된 적 없는 숫자에 선지불하지 않는다는 ADR-0012의 판단이 임계값 갱신에만 적용될 이유가 없다. 실측 후 필요가 드러나면 그때 여기서 시작한다.

## 다음 티켓이 알아야 할 것

- **#168 (앱 기기 세션 경계)** — 등록 요청은 `POST /api/v1/auth/device` + `Authorization: Bearer <등록 키>` + **본문 없음**이다. 세션 토큰을 붙이는 전역 인터셉터가 있다면 이 요청에서 **덮어써야** 한다(같은 헤더다). 거부는 **403**이고 이건 재등록으로 못 고친다 — 앱의 "401 → 재등록"이 여기로 흘러들면 안 된다. 응답의 `expires_at`은 **참고값**이라 타이머를 짜면 안 된다(슬라이딩이 서버에서 계속 민다).
- **#169 (런북)** — 파운더 콘솔 작업이 남았다: 시크릿 3개 생성(`cookmark-session-secret`·`cookmark-gemini-api-key`·`cookmark-register-key`) + **각각 두 SA**에 `secretAccessor`. 런타임 SA만 주면 서빙은 뜨는데 CI가 이미지 push **뒤** 마이그레이션 조회에서 403으로 죽는다. 등록 키는 **같은 값을 APK dart-define에도** 박아야 하고, 회전은 `versions add` → 새 리비전 배포 → 새 APK가 한 묶음이다.
