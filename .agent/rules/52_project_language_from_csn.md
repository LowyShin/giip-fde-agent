# 52. 프로젝트 응답 언어는 CSN 프로젝트 정보에서 자동 해석한다

> **HARD RULE** — 프로젝트(채널)의 AI 응답 언어는 CSN 의 giipdb 프로젝트 정보(`tCorp.cLang`)에서
> **자동으로** 가져와 설정한다. 프로젝트별로 언어를 수동 하드코딩하는 것을 1차 수단으로 쓰지 않는다.
> 근거: giip #1252 — https://giip.littleworld.net/ko/admin/giip-issues/1252
> 구현: `slack-bot/csn-lang-cache.js` + `slack-bot/config.js#resolveLangForProject`.

## 배경

이 메커니즘(csn → `tCorp.cLang` 자동 조회 → 응답 언어 결정)은 이미 구현돼 있고 동작도 확인됐다.
하지만 이를 설명하는 `.agent/rules/` 문서가 지금까지 없었다 — 그동안 `project-lang.json`(수동
언어 맵)에 이미 값이 들어가 있어서 "언어가 잘 맞는다"는 사실 자체가 CSN 자동해석이 작동한
결과인지, 수동 맵이 맞아서인지 구분되지 않은 채 넘어갔다.

규칙 문서가 없으면 향후 AI 에이전트가 이 사실을 모른 채 (a) 새 프로젝트를 추가할 때 언어를
`project-lang.json`에 수동으로 넣어야 한다고 가정하거나 (b) 언어 결정 로직을 코드 안에
하드코딩하거나 (c) 이미 있는 캐시/우선순위 메커니즘과 중복되는 별도 메커니즘을 새로 만들
위험이 있다. 이 문서는 **기존 동작을 바꾸지 않고** 그 동작을 공식 규칙으로 옮겨 적은 것이다
(Karpathy 원칙 — 동작하는 코드를 고치지 않는다, `.agent/rules/10_karpathy_guidelines.md`).

## 해석 순서(우선순위)

| 순서 | 수단 | 조건 |
|---|---|---|
| ① | `csn-lang-cache.peekCachedLangCode(csn)` — csn → `tCorp.cLang` 캐시(동기, 네트워크 없음). 성공 조회 TTL(`SUCCESS_TTL_MS`)은 **24시간(1일)** — 캐시 미스일 때만 API 를 부르고, 성공 값은 하루에 한 번만 재조회한다. 실패 TTL(`FAILURE_TTL_MS`)은 1분 그대로(변경 없음). | csn 을 알고 캐시에 유효한 히트가 있을 때 최우선 |
| ② | 수동 맵 `slack-bot/project-lang.json`(`loadProjectLangMap()`) | csn 미상, 캐시 미스, 또는 조회 실패(예: 403) 시 폴백 |
| ③ | `DEFAULT_LANG`(`'ko'`, `slack-bot/config.js`) | ①②모두 없을 때 최종 폴백 |

구현 지점: `slack-bot/config.js` `resolveLangForProject(projectName)`(219행 주석부터 226~235행
함수 본문)이 이 순서를 그대로 구현한다.

```js
// slack-bot/config.js:226-235 (발췌)
function resolveLangForProject(projectName) {
  const key = String(projectName || '').trim().toLowerCase();
  if (!key) return DEFAULT_LANG;
  const csn = resolveProjectCsn(key);
  if (csn != null) {
    const csnLang = require('./csn-lang-cache').peekCachedLangCode(csn);
    if (csnLang) return csnLang;
  }
  return loadProjectLangMap()[key] || DEFAULT_LANG;
}
```

## 규칙

1. **프로젝트 응답 언어가 필요한 모든 새 코드는 `resolveLangForProject(projectName)`
   (또는 동기 경로에서 `csn-lang-cache.peekCachedLangCode(csn)`)를 거쳐야 한다.** 언어를
   하드코딩하거나, 이 두 함수를 거치지 않는 별도의 언어 결정 로직을 새로 만들지 않는다.
2. **account+csn 이 함께 확보되는 지점에서 `csn-lang-cache.prefetch(account, csn)` 을
   fire-and-forget 으로 반드시 호출해 캐시를 채운다.** 현재 호출 지점은 두 곳이다 —
   `slack-bot/handlers.js` `triggerCsnLangPrefetch(channelId, projectName)`(48~59행)과
   `slack-bot/giip-task.js` `maybeCreateIssue(...)` 내부(54~58행, 이슈 생성 시점). 이 호출을
   빼먹으면 그 세션의 첫 응답은 캐시 미스로 항상 폴백 언어(②/③)로 나간다 — `prefetch` 결과는
   현재 응답에는 반영되지 않고 다음 메시지부터 캐시가 적용된다(fire-and-forget 설계상 당연한
   동작이며 버그가 아니다).
3. **`project-lang.json` 수동 맵은 CSN 조회가 실패하거나 CSN 매핑이 없는 프로젝트를 위한
   보조 수단일 뿐이다.** 신규 프로젝트를 추가할 때 "언어를 수동으로 넣어줘야 한다"고 가정하지
   않는다. 그 프로젝트의 csn 이 `resolveProjectCsn`으로 해석되고 CSN 의 `tCorp.cLang` 이 이미
   올바르게 설정돼 있으면, 수동 맵에 아무 것도 없어도 올바른 언어가 자동 적용된다.
4. **이 메커니즘의 동작(캐시 TTL, 해석 우선순위, 폴백 조건, `pApiCorpLangGetbySk` 의 SK 게이트
   방식 등)을 바꾸는 변경은 이 규칙 문서(52)도 함께 갱신한다.** 코드와 문서가 벌어지면 다음
   에이전트가 다시 "문서화 안 된 기존 동작"을 재발견하는 같은 상황이 반복된다.

## 알아둘 것 (버그 아님)

- `pApiCorpLangGetbySk`(giip-api.js `corpLangGet`, 281~289행)는 현재 하드코딩된 단일 Admin SK
  게이트라, 이 레포가 쓰는 테넌트 SK(`account.sk`)로는 403 이 날 수 있다. 이는 설계상 정상
  실패 경로로 취급돼 짧은 TTL(`FAILURE_TTL_MS`=1분)로 캐시되고 ②/③ 으로 조용히 폴백한다
  (`csn-lang-cache.js` 15~17행, 266~273행 주석 참고). 이 403 자체를 "고쳐야 할 버그"로 오인하지
  말 것 — giipdb 쪽 SP 완화 또는 전용 admin SK 프로비저닝이 필요한 별도 후속 과제다(이번 범위
  밖).
- 캐시는 프로세스 재시작에도 살아남도록 `slack-bot/.csn-lang-cache.env`(git-ignored, dotenv 형식)에
  write-through 로 영속화된다(csn-lang-cache.js 18~22행).
- 캐시 성공 TTL(`SUCCESS_TTL_MS`)은 **2026-10-05 사용자 지시로 5분 → 24시간(1일)으로 변경됐다.**
  목적: CSN 언어 확인을 위해 매 트리거마다/5분마다 giipdb API(`pApiCorpLangGetbySk`)를 반복 호출하지
  않고, 영속 캐시 파일(`.csn-lang-cache.env`)을 1차 소스로 삼아 캐시 미스일 때만 API 를 부르고
  성공 값은 하루에 한 번만 재조회하도록 바꾼 것이다. `FAILURE_TTL_MS`(1분, 실패 캐시)는 변경하지
  않았다 — 전송 오류가 길게 방치되지 않아야 하기 때문이다. 혼동 방지: 두 TTL 은 서로 다른 값이고
  이번 변경은 성공 TTL 에만 적용된다.

## 상호참조

- `slack-bot/csn-lang-cache.js` — `peekCachedLangCode(csn)`(동기 피크), `prefetch(account, csn)`
  (백그라운드 조회+캐시 채움), 영속 캐시 파일 IO.
- `slack-bot/config.js` — `resolveLangForProject(projectName)`(219~235행), `DEFAULT_LANG`(172행),
  `loadProjectLangMap()`(192~194행).
- `slack-bot/giip-api.js` — `corpLangGet(account, csn)`(266~289행, SP `pApiCorpLangGetbySk` 호출).
- `slack-bot/handlers.js` `triggerCsnLangPrefetch`(48~59행), `slack-bot/giip-task.js`
  `maybeCreateIssue`(54~58행) — prefetch 호출 지점.
- [`10_karpathy_guidelines.md`](10_karpathy_guidelines.md) — surgical changes 원칙, 이 문서가
  동작을 바꾸지 않고 문서화만 하는 이유.
- [`51_giip_product_changes_csn47_only.md`](51_giip_product_changes_csn47_only.md) — 포맷 참고용
  선행 규칙 파일(이 문서와 무관한 주제지만 동일한 구조를 따름).
