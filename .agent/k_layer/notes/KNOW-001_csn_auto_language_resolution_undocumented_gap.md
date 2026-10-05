# KNOW-001: CSN 기반 응답 언어 자동해석은 이미 구현돼 있었으나 규칙 문서가 없었다

- 근거: giip #1252 — https://giip.littleworld.net/ko/admin/giip-issues/1252
- 작업 CSN: 70424
- 관련 파일: `slack-bot/csn-lang-cache.js`, `slack-bot/config.js#resolveLangForProject`,
  `slack-bot/giip-api.js#corpLangGet`, `slack-bot/handlers.js#triggerCsnLangPrefetch`,
  `slack-bot/giip-task.js#maybeCreateIssue`
- 신규 규칙: `.agent/rules/52_project_language_from_csn.md`

## 원인분석

giip #1252 요구사항("csn 이 인식되면 그 csn 의 cLang 을 읽어 그 언어로 답변")은 이미 코드로
구현돼 있었고 실제로 동작도 하고 있었다(사용자 확인). 그러나 이 메커니즘을 설명하는
`.agent/rules/` 문서가 지금까지 하나도 없었다. 사용자가 이를 깨달은 계기는 "지금까지
`project-lang.json`(수동 언어 맵)에 이미 언어가 잘 들어가 있어서 신경 쓸 필요가 없었는데,
그게 CSN 자동해석 덕분인지 수동 맵 덕분인지 구분이 안 된 채 넘어갔다"는 것이었다.

구현을 다시 읽어 확인한 해석 우선순위:
1. `csn-lang-cache.peekCachedLangCode(csn)` — csn → `tCorp.cLang` 캐시(동기, 네트워크 없음).
2. 수동 맵 `project-lang.json`(`loadProjectLangMap()`).
3. `DEFAULT_LANG`('ko').

캐시를 채우는 `prefetch(account, csn)` 은 `handlers.js`(`triggerCsnLangPrefetch`)와
`giip-task.js`(`maybeCreateIssue`) 두 지점에서 account+csn 이 함께 확보될 때
fire-and-forget 으로 호출된다. `pApiCorpLangGetbySk` 가 현재 Admin SK 단일 게이트라 테넌트
SK 로는 403 이 날 수 있는데, 이는 설계상 정상 폴백 경로로 취급된다(짧은 TTL 로 캐시).

## 재발방지

문서화 누락 자체가 결함은 아니지만, 문서가 없으면 향후 에이전트가 이 메커니즘을 모른 채
(a) 언어를 하드코딩하거나 (b) `project-lang.json` 수동 등록을 신규 프로젝트의 필수 절차로
오해하거나 (c) 중복 메커니즘을 새로 만들 위험이 있었다. `.agent/rules/52_project_language_from_csn.md`
를 신설해 기존 동작(변경 없음)을 공식 규칙으로 옮겨 적고, `CLAUDE.md` 의 "GIIP PRODUCT SCOPE"
섹션 바로 뒤에 같은 스타일로 "PROJECT RESPONSE LANGUAGE — AUTO-RESOLVED FROM CSN" 섹션을
추가해 진입점에서 링크했다(rule 70 — 지시는 정본에 남기고 진입점에서 링크).

## 결과가 저장되는 곳

- 규칙 정본: `giip-fde-agent/.agent/rules/52_project_language_from_csn.md`(git-tracked).
- 진입점 링크: `giip-fde-agent/CLAUDE.md` "PROJECT RESPONSE LANGUAGE" 섹션.
- 이 노트: `giip-fde-agent/.agent/k_layer/notes/KNOW-001_csn_auto_language_resolution_undocumented_gap.md`
  + `INDEX.md`.
- tKB: CSN 70424 로 `node <lowyworkenv>/scripts/gissue/tkb.js sync-klayer --csn 70424 --dir
  .agent/k_layer/notes` 동기화 시도(세션 보고 참고 — 성공 여부는 완료 보고에 명시).

## 소비처

다음에 이 레포에서 언어 관련 코드를 만지거나 신규 프로젝트를 온보딩하는 에이전트/사람이
`.agent/rules/52_project_language_from_csn.md` 를 먼저 읽고 기존 메커니즘을 재사용하도록 함.

## 추가: 캐시 성공 TTL 5분 → 24시간 변경 (2026-10-05 사용자 직접 지시)

사용자 요청: "언어 체크를 위해 매번 api호출하는게 아니고 언어 정보가 config파일에 없으면 api로
불러와서 config파일을 기준으로 하루에 한 번만 업데이트 되게 해줘." 당시 이미 "캐시 미스 시
API 호출 + `.csn-lang-cache.env` 영속화" 구조는 구현돼 있었으므로, 바꿀 것은
`csn-lang-cache.js` 의 `SUCCESS_TTL_MS` 값 하나였다(5 * 60 * 1000 → 24 * 60 * 60 * 1000). 캐시
조회/쓰기 로직, `peekCachedLangCode`/`prefetch` 인터페이스, `resolveLangForProject` 의 우선순위
(①캐시→②수동맵→③DEFAULT_LANG)는 변경하지 않았다(surgical change, rule 10). `FAILURE_TTL_MS`
(1분, 실패 캐시)도 그대로 유지했다 — 전송 오류를 길게 방치하지 않기 위해서다.

목적/효과: 영속 캐시 파일(`.csn-lang-cache.env`)을 1차 소스로 삼아, 캐시가 채워진 상태에서는
트리거마다/5분마다 giipdb API(`pApiCorpLangGetbySk`)를 다시 호출하지 않고 성공 값은 하루에 한
번만 재조회한다. 함께 갱신한 파일: `slack-bot/csn-lang-cache.js`(28행),
`.agent/rules/52_project_language_from_csn.md`(해석 순서 표 ①항목 + "알아둘 것" 섹션에 TTL 값과
근거 날짜 명시). 이 변경에는 별도 giip 이슈 번호가 없다 — 근거는 "사용자 직접 지시(2026-10-05,
이 대화)"뿐이다.
