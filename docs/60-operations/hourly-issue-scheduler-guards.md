# 매시 이슈 처리 스케줄러 표준 스펙 — 가드·로딩 상세

> 본문(정본): [hourly-issue-scheduler.md](./hourly-issue-scheduler.md) 에서 분리된 절
> 모음이다 (giip #6329 — 500라인 초과 분리). 절 번호는 본문과 동일하게 유지한다.
> 담는 절: 미매핑 CSN 가드 · slack-bot PR 없는 완료 보고 · §19 프로젝트 정보 로딩 · §20 코멘트 작성자 aiName

## 미매핑 CSN 가드(Phase -2.5) — 정본 기준 판정 + 응답 cSn 대조 (giip 4116 / 4139)

- 용도: `csn-projects.json` 에 없는 csn 에 열린 이슈가 방치돼 있는지 감시한다.
- 판정 로직은 `lib/unmapped-csn-guard.ps1` 로 분리했다(러너와 회귀 테스트가 **같은 함수**를 쓴다 —
  러너 안의 top-level 함수였다가 "실제 호출 경로"를 회귀 테스트가 건드릴 수 없었다).
- 처리 2단계:
  1. **정본 기준 판정** — 판정 재료는 **정본** `tGissueCsnMapping` 이다(로컬 `csn-projects.json` 만 믿지 않는다).
     조회: `lib/get-csn-mapping.js`(`/api/giipGissueCsnMapping?csn=<N>`), 3값 판정(`Get-GissueCanonicalMappingStatus`).
     - `MAPPED`(정본에 등록+활성) -> `SKIP-MAPPED-CANONICAL` — **담당 배포가 있으므로 아무것도 하지 않는다**.
     - `UNMAPPED`(정본에 없음이 **확인**됨: 404/빈 결과, 또는 비활성 행) -> 게시 대상.
     - `UNKNOWN`(정본 조회 불가: 403 스코프/전송 오류/파싱 실패/행 이상) -> `SKIP-CANONICAL-UNKNOWN` —
       **아무것도 쓰지 않는다**(fail-closed). 로컬 파일로 되돌아가지 않는다. `UNKNOWN` 을 `UNMAPPED` 로
       취급하면 "정본에 등록된 csn 을 담당 없음" 으로 오판하는 거짓 양성이 되살아난다.
  2. **응답 cSn 대조** — 후보 csn 을 `list-issues.js --json` 으로 조회하되, **응답 행의 실제 `cSn` 이 요청 csn 과
     같은 행만** 신뢰한다(`lib/csn-guard.ps1` 의 `Select-GissueRowsMatchingCsn`). 서버는 멤버가 아닌 csn 요청을
     홈 csn 으로 조용히 클램프할 수 있으므로, 요청값을 그대로 붙이면 다른 csn 의 이슈가 "미매핑 csn 의 방치
     이슈"로 오인된다.
     - `cSn != 요청 csn` -> `SKIP-CLAMP`, `cSn` 없음 -> `SKIP-NOCSN`: 행을 버리고 로그만 남긴다(기본은 침묵).
- 게시: 원래 이슈들에는 **코멘트를 남기지 않는다**(2026-10-22 거짓 양성 코멘트 사고의 직접 원인).
  게시 단위는 **csn 1건**이며, 운영 이슈 1건(`[OPS] csn <N> 담당 배포 없음 — 이슈 <건수>건 방치`)은 환경변수
  `GISSUE_CSNGUARD_OPS_CSN` 이 지정된 때만 해당 csn 에 등록하고, 미지정이면 `SKIP-NOOPSCSN` 로그만 남긴다.
- 정본 조회 응답 형식 주의(giip 4116 의 거짓 양성 원인): `/api/giipGissueCsnMapping` 은 행을 **배열**로 돌려준다
  (`{"message":"OK","ok":true,"count":1,"mapping":[{"gcmCsn":…,"gcmEnabled":…,"gcmProjectName":…,"gcmWorkdir":…}]}`).
  한 행 객체로 가정하면 전부 `scope_mismatch` 로 오판되어 **정본에 등록된 csn 을 "미매핑"** 으로 봤다.
  `lib/get-csn-mapping.js` 가 배열 컨테이너와 래핑(`mapping`/`rows`/`data`/`row`)을 모두 정규화하고,
  요청 csn 과 일치하는 행만 채택한다.
- Phase -2.5 **사전 패스(로컬 맵에 없는 csn 을 정본으로 결정해 로컬 맵에 채택)는 제거**했다(2026-11-23, giip 4116):
  정본 응답 해석이 고쳐지며 그 채택이 **처음으로 실제로 동작**하게 되고, 그 결과 이 배포(CSN 70424)가
  csn 47/70335/70428 같은 **타 CSN 을 통째로 떠안게** 된다(= CSN 경계 위반). 정본 판정은 위 가드가
  **읽기 전용**으로 하므로, 채택은 Phase -3(1-b2)의 "이미 이 배포가 주장한 csn" 채우기만 남긴다.
- 저장: `logs/gissue_csnguard.log` 에 `POSTED` / `SKIP-*` / `OK` 를 매 실행 기록한다. `list-issues.js --json`(및 `--queue --json`)은 각 행에 `cSn` 을 포함한다.
- 소비처: 이 로그를 운영자가 읽는다.
- 회귀 테스트: `scripts/gissue/tests/test-unmapped-csn-guard.ps1`(오프라인 — 정본 3값 판정·cSn 대조·게시 단위),
  `scripts/gissue/tests/test-csn-guard-clamp.ps1`(응답 cSn 대조), `scripts/gissue/tests/test-csn-mapping.mjs`(배열 응답 계약).
  라이브 실측(실서버·실 SK 필요, CI 게이트 대상 아님): `scripts/gissue/tests/live/test-unmapped-csn-guard-live.ps1`
  — 게이트 기대 건수(`run-repo-gates.ps1` 의 `$ExpectedPs1TestCount`)에는 넣지 않는다(SK·네트워크가 없으면 SKIP=종료코드 3).

## slack-bot 의 PR 없는 조사/답변형 완료 보고 (giip 4231)

- 용도: 코드 변경·PR 이 없는 조사/점검/답변형 태스크가 끝났을 때, PR 완료 게이트(`pr-gate-sweep.ps1`)가 "대응 PR 없음"으로 REVIEW 이슈를
  READY 로 되돌리는 도돌이표를 막고, 실행자 결론을 giip 코멘트에 남긴다.
- 처리: `slack-bot/handlers.js` `onComplete` 가 REVIEW 전이 코멘트에 `## 실행자 결론`(결과물 4000자 클립)을 포함한다.
  PR 이 하나도 없고(`allUrls` 비어 있음) 결론이 있으면, REVIEW 전이 **전에** 첫 줄이 `[NO-PR-REASON]` 인 독립 코멘트를
  `giip-task.maybeCommentRaw`(행위자 헤더 없음)로 남긴다. 본문은 의뢰 요약 / 요청 항목별 결과 / 실행자 결론 / 최종 판정이다
  (`slack-bot/no-pr-report.js`, 문구는 `i18n-ui.js` ko/en/ja). 상태전이 사유(Why)에 적는 것은 게이트가 인정하지 않는다
  (`giip-api.issueUpdate` 가 `## [actor] 상태전이` 를 첫 줄로 붙이기 때문).
- 저장: 코멘트는 `giipIssueComments`(tGiipIssueComment) 에 저장된다. 소비처: `gissue-audit-lib.ps1` `Test-HasNoPrReasonMarker` ->
  보고형 완료 판정(`Invoke-ReportCompletionJudge`, giip 3801)이 의뢰와 결과를 대조해 FULFILLED 면 DONE, 아니면 되돌린다.
- 범위 밖: `onError`(에러 종료)는 완료 주장이 아니므로 마커를 남기지 않는다. 테스트: `slack-bot/tests/no-pr-report.test.js`.

## 19) 프로젝트 정보 로딩 — 로컬 매핑 부족 시 GIIP 매핑 조회 폴백 (giip 5664)

> 배경: 러너는 이슈의 작업 환경을 호스트 로컬 `csn-projects.json`에서만 결정해 왔고, 항목이 없거나 placeholder인 CSN은 GIIP 쪽 정본을 확인할 길이 없었다(낡은 로컬 매핑 그대로 진행하거나 조용히 건너뛰는 사고 — 빈 폴더에서 세션이 시작하는 부류). DB 정본은 `tGissueCsnMapping`(giip #2363)이지만 DB→JSON 동기화는 별도 결함으로 막혀 있고, 동기화 스크립트(`sync-csn-mapping-from-db.ps1`)는 DB 직접 접속 전제라 **DB 직접 접근이 없는 이 레포에는 이식 대상이 아니다**(§13-2 격차). 그래서 동기화 복구가 아니라 **조회 폴백**으로 대체한다.

### 19-1. 결정 구조

| 로컬 항목 | GIIP 매핑 조회 | 결과 |
|---|---|---|
| 충분(`Test-GissueCsnEntryValid` 통과) | **하지 않음** | 로컬 항목 그대로 (현행 동작) |
| 없음/placeholder | 행 있음 + 병합 항목도 유효 | 원격 값으로 결정 + 캐시 기록 (`[CSN-MAP]` 로그) |
| 없음/placeholder | 없음(404)·스코프 불일치(403)·행 자체가 placeholder | UNMAPPED — 추측 진행 금지, 보고는 Phase -2.5 미매핑 감시 경로 |
| 없음/placeholder | 조회 실패(네트워크·미배포·SK 없음) | UNMAPPED와 동일하게 fail-soft — 로그만 남기고 현행 동작 유지 |

- `csn-projects.json`의 지위: 수기 편집 파일이 아니라 **로컬 우선 + GIIP 폴백으로 채워지는 캐시**다. 사람이 손으로 넣은 충분한 항목은 조회 대상이 아니며, 폴백 병합은 로컬에만 있는 선택 필드(`restBranch`·`note` 등)를 지우지 않는다.
- 판정의 단일 출처: 항목 충분 여부는 러너의 `Test-GissueCsnEntryValid`를 주입받아 쓰고, LOCAL/REMOTE/UNMAPPED 결정은 `scripts/gissue/lib/csn-mapping.ps1`의 `Resolve-GissueCsnMapEntry` 한 곳에서만 한다.

### 19-2. 배선 (1곳)

1. **Phase -3 직후 패스**: 매핑 파싱이 끝나면 전 항목을 대상으로 부족분을 조회·보완한다. placeholder 검사(1-c)와 "유효 항목 0건이면 치명" 판정보다 **먼저** 돌므로, 로컬이 전부 낡아도 GIIP 매핑으로 복구되면 실행이 계속된다. 이 패스의 결정은 이번 실행의 Phase 1부터 적용된다. **이 배포가 이미 주장한 csn** 만 대상이다.

> **[제거] Phase -2.5 사전 패스(2026-11-23, giip 4116)** — "매핑 파일에 아예 없는 후보 CSN" 을 정본으로 결정해
> 캐시에 넣던 패스는 제거했다. 정본 응답 해석(배열 컨테이너)이 고쳐지며 이 채택이 **처음으로 실제로 동작**하게 되고,
> 그 결과 이 배포(CSN 70424)가 csn 47/70335/70428 같은 **타 CSN 을 통째로 떠안게** 된다(= CSN 경계 위반).
> "미매핑" 판정은 이제 읽기 전용 가드(`lib/unmapped-csn-guard.ps1`)가 정본 기준으로 내리므로, 감시 결과는
> 사라지지 않고 **판정 근거만** 바뀐다(로컬 맵 → 정본).

- `-DryRun`에서는 캐시 파일을 쓰지 않는다(판정·로그만). 캐시 기록은 임시 파일에 써서 교체하므로 중간에 죽어도 원본이 깨지지 않는다.

### 19-3. 읽기 경로 계약 (스코프드 byAK)

- `GET {apiBase}/giipGissueCsnMapping?csn=<n>`, 헤더 `x-api-key: <그 CSN의 SK>`.
- AK에서 도출되는 CSN과 요청 CSN이 일치할 때만 그 CSN의 행 1건(`csn`·`projectName`·`workdir`·`enabled`)을 반환한다. 불일치는 403, 없음은 404.
- 기존 `pApiGissueCsnMappingListbyAK`(sysadmin 전용·전체 반환)는 이 용도로 쓰지 않는다.
- 응답의 `csn`이 요청과 다르면 채택하지 않는다(큐 조회의 cSn 대조와 같은 방어 — `lib/get-csn-mapping.js`의 `parseMappingResponse`).
- SP·엔드포인트 구현은 별도 작업으로 분리했다 — giip #5665. CSN별 상태 정의(giip #5572)의 읽기도 같은 스코프드 byAK 패턴으로 통일한다.
- 조회 헬퍼: `scripts/gissue/lib/get-csn-mapping.js` (사용법·출력 형식은 파일 헤더).

### 19-4. 운영자가 채울 것

- GIIP 프로젝트 상세(매핑)의 `gcmProjectName`·`gcmWorkdir`·`gcmEnabled`가 폴백의 정본 값이다. `gcmWorkdir`는 그 CSN의 이슈를 처리할 폴더의 절대경로로 채운다 — 비어 있거나 placeholder면 폴백이 성립하지 않는다(remote_invalid).

### 19-5. 테스트

- `scripts/gissue/tests/test-csn-mapping-fallback.ps1` — 판정(LOCAL/REMOTE/UNMAPPED·remote_invalid·fail-soft), 병합의 로컬 필드 보존, 캐시 기록(타 항목·최상위 키 보존, 파일 부재 시 생성 안 함), 오케스트레이션, 후보 수집, 소스 커플링.
- `scripts/gissue/tests/test-csn-mapping.mjs` — 응답 해석(camelCase/gcm 접두사/래핑, enabled 강제 변환, 스코프 불일치 차단)과 엔드포인트 계약 문자열.
## 20) 코멘트 작성자 — 로컬 AI 이름(`aiName`) 단일 출처 (giip 5667)

> 배경: 코멘트 author는 인증에 쓴 키로 서버가 확정한다(giip #2613의 actor 체계). 그런데 주체 선택이 스크립트마다 `$env:GIIP_ACTOR = 'ai.dp01.gissue-scheduler'`로 하드코딩돼 있어, 어느 호스트에서 돌려도 dp01 스케줄러 이름으로 기록됐다. 여러 인스턴스가 작업해도 **작업한 AI가 코멘트에 남아야** 하므로, 이름을 로컬 설정에서 읽는 구조로 바꾼다.

### 20-1. 단일 출처: `csn-projects.json` 최상위 `aiName`

```json
{ "aiName": "ai.dp01.gissue-scheduler", "csn": { "...": "..." } }
```

- 값은 `scripts/gissue/ai-actors.json`에 등록된 actor key(`ai.<host>.<process>` 명명 규칙)여야 한다. 새 이름이 필요하면 먼저 `scripts/gissue/AI_ACTOR_ACCOUNTS.md` 절차로 계정·AK를 등록한다 — **설정에만 적고 등록이 없으면 해석이 실패한다**.
- 왜 이 파일인가: ① 스케줄러 배포마다 반드시 존재하는 유일한 로컬 설정 파일이다. `giipAgent.cfg`는 선택 사항(heartbeat 미설정 배포가 존재)이고 giipAgent라는 다른 프로그램의 파일이라 스케줄러 인스턴스의 정체성을 담기 부적합하다(`ai_name=` 안은 이 이유로 기각). ② 레지스트리·해석기와 같은 폴더라 해석기가 자기 위치 기준으로 읽는다. ③ 파일이 인스턴스(PC)마다 분리돼 있어(gitignore) "인스턴스마다 자기 이름"과 정확히 대응한다.

### 20-2. 해석 순서 (정본: `lib/resolve-actor.js`의 `pickActorKey`)

1. 호출 인자 `actorKey`
2. 환경변수 `GIIP_ACTOR`
3. **`csn-projects.json`의 `aiName`**
4. `ai-actors.json`의 `defaultActor`

- 러너는 매핑 파싱 직후(Phase -3) 해석 결과를 `$env:GIIP_ACTOR`로 확정해 자식 프로세스(claude CLI → get-issue.sh)까지 같은 이름이 상속되게 하고, 상태를 `[ACTOR]` 로그로 남긴다. 독립 스크립트(review-done-audit, pr-gate-sweep, pr-attribution-sweep, review-merged-presweep, page-feedback-analyze)도 같은 해석을 탄다 — 하드코딩된 actor 할당은 두지 않는다.
- REVIEW 재검증 쿨다운의 "자기 author" 목록에는 고정 목록에 더해 확정된 주체(`$env:GIIP_ACTOR`)를 동적으로 포함한다 — 호스트마다 이름이 달라도 자기 코멘트를 새 신호로 오인하지 않기 위해서다.

### 20-3. 미설정·무효일 때 — 표시 이름은 hostname으로 (보완 지시)

인증 주체와 **표시 이름은 별개 채널**이다. 인증은 위 해석 순서(actor AK 체계)를 따르고, 코멘트와 함께 보내는 표시 이름(`author` 필드)은 다음 순서로 정한다 — 정본은 `lib/resolve-actor.js`의 `pickAuthorDisplayName`/`resolveAuthorDisplayName`, 전송은 `lib/post-comment.js`가 게시마다 실어 보낸다.

1. 로컬 AI 이름 (`GIIP_ACTOR` 환경변수 > `csn-projects.json`의 `aiName`)
2. **이 장비의 hostname**
3. 그것도 만들 수 없을 때만 보내지 않는다(서버 폴백)

- **미설정**: 'Agent' 같은 공통값으로 뭉개지 않는다 — 인스턴스 구분이 이 구조의 목적이라, 이름이 없으면 hostname이 그 인스턴스의 구분자다. 러너는 `[ACTOR] … aiName 미설정 — 표시 이름은 hostname으로 전송` 로그를 남긴다.
- **무효(레지스트리에 없는 이름·AK 없음)**: 인증 해석은 실패한다(조용한 폴백으로 사람 이름이 찍히는 상태를 막는 것이 #2613의 원칙). 러너는 `[ACTOR] … 해석하지 못했습니다` 로그를 남기고 기본 폴백으로 계속 실행한다. 표시 이름은 위 순서대로 정해져 함께 전송된다.
- 표시 이름이 최종 author 표시로 남는 것은 서버측 표시 보존 개편(giip #5663 계열)이 배포된 뒤다. 그전까지 기존 엔드포인트는 `author` 필드를 무시할 수 있으며, 무시돼도 게시 동작은 기존과 같다.

### 20-4. 외부 인스턴스(Muse 등)에 대한 규칙

- 이 스케줄러를 직접 돌리지 않는 인스턴스라도, giip 코멘트를 게시할 때는 같은 규칙을 따른다: 자기 배포의 `csn-projects.json`에 `aiName`을 두거나 `GIIP_ACTOR` 환경변수로 자기 actor key를 지정하고, 게시에는 그 actor의 AK를 쓴다. SK로 게시하면 author가 SK 소유 계정으로 찍힐 수 있다.
- 서버측 표시 보존(AT로 해석되는 키에서도 클라이언트 이름을 최종 표시로 남기는 개편)은 별도 프로젝트에서 진행한다 — 이 절은 에이전트(로컬) 쪽 규칙만 다룬다.
- 코멘트 **본문 안의 라벨**(`gissue-review-audit` 등 자기 과거 코멘트 탐색용)은 이 구조의 대상이 아니다. 바꾸는 것은 인증 주체(계정) 선택뿐이다.

### 20-5. 테스트

- `scripts/gissue/tests/test-resolve-actor.mjs` — 해석 우선순위(인자/환경변수/aiName/기본값)와 출처 표기, `readLocalAiName`(trim·BOM·깨진 파일·미존재)의 무예외 폴백.
- `scripts/gissue/tests/test-ai-name.ps1` — PS 스크립트에 하드코딩 actor 할당이 남지 않았음, 러너의 aiName 확정·[ACTOR] 로그·쿨다운 목록 동적 포함, 독립 스크립트의 해석 경유를 소스 단언으로 고정.
