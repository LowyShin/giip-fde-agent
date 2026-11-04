# CSN 70424 — giip 4219 Jev 의도 분류 사양서 §9/§10-2 상태 동기화 (2026-11-04 20:06 KST)

## 세션 정체

- 작업 CSN: **70424** · 프로젝트: `giip-fde-agent`
- 이슈: **giip 4219** — "[Jev 의도 분류] slack-bot 의 task/question 분류에 Jev 도입 (상위)"
  (https://giip.littleworld.net/ko/admin/giip-issues/4219)
- **상위 수렴 이슈** — 4219 자체 소스 변경은 없다. 산출물은 ① 사양서 ② lowyworkenv `MODEL_USAGE_SPEC.md` 계획 항목(D) ③ 서브 이슈 A~C 완료분.
  이번 세션의 산출물은 **① 사양서 §9 서브 이슈 대응표·§10-2 를 실측 상태에 맞춰 정정**한 것이다.
- **공유 체크아웃(`C:\Users\lowys\Downloads\projects\giip-fde-agent`)은 수정하지 않았다.** 전용 워크트리에서만 작업했다.

| 워크트리 | 대상 레포 | 기준 | 브랜치 |
|---|---|---|---|
| `D:\temp\worktrees\giip-fde-agent\giip4219-spec-status` | giip-fde-agent | `origin/main` = `2a2318d` | `docs/giip-4219-jev-spec-status-20261104` |

## 왜 이 변경이 필요했나 (근거)

rule 55 §1 — "상위 문서가 코드·실측과 다르면 코드·실측을 기준 삼는다, **틀린 문서는 발견 즉시 정정한다**".

사양서 `slack-bot/docs/INTENT_ROUTING_JEV_SPEC.md` §9 는 자기 제목이 "**하위 작업 분해 (서브 이슈 대응표)**" 인데,
표 안의 상태 서술이 실측과 어긋나 있었다(2026-11-04 11:01 UTC 실측):

| §9 원문 | 실측 | 판정 |
|---|---|---|
| (B) "구현 완료(**PR 대기**)" | PR #368 **MERGED** 2026-11-04T02:27:12Z (`a1fc168`) | 틀림 |
| (A) "구현 완료(PR 대기)" · "배치 결정 … (C)(D) 는 미구현" | (A) 는 **DONE**(giip 4220) | 틀림 |
| (B) "… (C)(D) 는 미구현" | (C) 는 **DONE**(giip 4222 · PR #369 `d70cb91`) · (D) 는 **MERGED**(lowyworkenv PR #1101) | 틀림 |
| D "별도 PR 로 **진행 중**" | lowyworkenv PR #1101 **MERGED** 2026-11-04T00:17:07Z | 틀림 |
| §10-2 "(C) 전에는 정확도를 주장하지 않는다" | (C) 평가 완료 — 38건 코퍼스 기준 89.5%→92.1% · Jev 라우팅 13건 오류 0 | 낡음 |
| §9 표에 서브 이슈 번호·링크 없음 | §9 제목이 "서브 이슈 대응표" 인데 대응 대상이 표에 없음 | 결손 |

→ 상위 이슈(4219)가 §9 의 대응표 소관자이므로, 이 정정은 4219 소관 작업이다.

## 변경 내용 (PR #382 = 3파일 · PR #383 = 4파일)

| 파일 | 변경 | PR |
|---|---|---|
| `slack-bot/docs/INTENT_ROUTING_JEV_SPEC.md` | §9 대응표에 **서브 이슈 열**(giip 4220/4221/4222 + 4219 링크)과 **상태 열** 추가 · (A)(B)(C)(D) 상태 단락을 실측값으로 교체 · (B) 에 남은 2건(verify 블록 Node 24 거짓음성 · §10-1 마스킹 소급 사용자 결정) 기재 · §10-2 정확도 서술을 (C) 결과 반영으로 갱신 · 헤더 "갱신" 이력에 §9·§10-2 반영 표기 | #382 |
| `docs/WHATS_NEW.md` | rule 36 — 이번 변경 항목 추가(기준일 `2026-11-04` 는 이미 동일) | #382 |
| `.agent/work_history/20261104_2006_csn70424_giip-4219-jev-spec-status-sync.md` | 신규 — 이 기록 | #382 (2차 PR 에서 계속 갱신) |
| `.agent/k_layer/notes/KNOW-037_node24_test_directory_arg_false_negative_UNDETERMINED_verify_block.md` | 신규 — Node 24 `node --test <디렉터리>` 거짓음성 → verify 블록이 완료조건을 잘못 FAIL 로 만드는 구조 (tKB kbSn 6968) | #383 |
| `.agent/k_layer/notes/INDEX.md` | KNOW-037 행 추가 (근거·kbSn) | #383 |
| `scripts/privatekb/README.md` | **함정 6** 추가 — `list --search` 는 제목만 검색한다(본문 미검색) · `put` 의 `--ref-type` 은 신규 생성에만 적용 | #383 |
| `docs/WHATS_NEW.md` | KNOW-037·tKB 등록 내용 반영 (같은 항목 안) | #383 |

**별도 커밋 1건(rule 54 자가 검사에서 발견한 사전 위반 즉시 정정)** — `docs/WHATS_NEW.md` 의 저장소 위생 정비 83·84·85차 항목에
남아 있던 **다른 CSN 번호와 고객 프로젝트 식별자 3건**을 `<csn>` 플레이스홀더로 치환했다.
이 저장소 자신의 CSN(70424) 은 rule 54 예외 대상이라 그대로 둔다. 이 건은 4219 의 의뢰와 무관하므로 **별도 커밋**으로 분리했다.

**§10-2 는 "정확도 미확인" 을 지우지 않았다.** (C) 결과는 38건 코퍼스 기준이므로 **범용 한국어·일본어 정확도는 미확인** 이라는 결론을 유지하고,
측정된 범위(92.1% · Jev 라우팅 13건 오류 0 · engine `jev-1.14.0`)와 미확인 범위를 나란히 적었다.

## PR · CI 결과 (PR 완료 게이트)

| 항목 | 값 |
|---|---|
| PR | **#382** — https://github.com/LowyShin/giip-fde-agent/pull/382 · `docs/giip-4219-jev-spec-status-20261104` → `main` |
| PR CI(run `41819207498`) | GitGuardian **pass**(1s) · MJS gates **pass**(39s) · PS1 gates **pass**(1m42s) — **전부 green** |
| 머지 | **MERGED** 2026-11-04T11:20:15Z · 커밋 **`e7d9b4e`** (squash) |
| main CI(run `41820079874`) | **success** (headSha `e7d9b4e`) — 머지 후 main 도 green |
| mergeStateStatus | `CLEAN` (충돌 0) |

**PR-ATTRIBUTION 코멘트(2026-11-04T11:13:56Z) 대조 결과 — 오탐이었다.**
그 코멘트는 "이 이슈의 PR #382" 에 대해 "먼저 머지된 무관한 PR #381 이 `docs/WHATS_NEW.md` 를 먼저 바꿔
충돌 해소 후 머지가 필요하다" 고 알렸으나, **#381 의 머지 커밋 `2a2318d` 가 #382 의 baseRefOid 그 자체**였다
(`gh pr view 382 --json baseRefOid` = `2a2318d3fdd5015b2f631e05b99e01eadb5cd376` = PR #381 의 mergeCommit).
→ `git merge-base --is-ancestor 2a2318d HEAD` = **참**(조상). `git diff origin/main -- docs/WHATS_NEW.md` 는
**이번 세션 추가분만** 보여주고 #381 이 넣은 97·98·99차 항목을 지우지 않았다. 실제 충돌은 0건이었다.
코멘트가 지시한 "main 에 먼저 들어간 파일의 내용이 이 이슈의 완료조건을 충족하는지 직접 확인" 도 수행했다 —
`git cat-file -e origin/main:slack-bot/docs/INTENT_ROUTING_JEV_SPEC.md` → **exit 0** (완료조건 ① 충족).

## 실행 증거

| 검증 | 결과 |
|---|---|
| `git -C giip-fde-agent cat-file -e origin/main:slack-bot/docs/INTENT_ROUTING_JEV_SPEC.md` | exit 0 (사양서 존재 — 완료조건 ①) |
| `git -C lowyworkenv show origin/main:MODEL_USAGE_SPEC.md \| grep -qi 'jev'` | exit 0 (완료조건 ②) |
| `node scripts/gissue/verify-runner.mjs 4219 70424 --comment --json` | **PASS · exit 0** · 검사 1건 exit 0 (12400ms) — verify 블록은 ①② 만 검사한다 |
| `node scripts/gissue/lib/get-isn-status.js <api> <sk> 4220,4221,4222` | `4220\|DONE` · `4221\|NEEDS_DECISION` · `4222\|DONE` (exit 0) · all-DONE 판정 awk → **exit 1** (완료조건 ③ 미충족) |
| `gh pr view 368 / 369` | 둘 다 **MERGED** (2026-11-04T02:27:12Z / 02:56:58Z) |
| `git cat-file -e origin/main:slack-bot/docs/INTENT_ROUTING_JEV_EVAL.md` · `.../slack-bot/tests/intent-jev.test.js` | 둘 다 exit 0 |
| `node --test slack-bot/tests/` (디렉터리 인자) | **exit 1** — `Cannot find module '…\slack-bot\tests'` (Node v24.13.0) |
| `node --test "slack-bot/tests/*.test.js"` (글로브) | **exit 0** — tests 60 / pass 60 / fail 0 |
| `gh pr checks 1101` (lowyworkenv) | GitGuardian Security Checks: **pass** |

### 이 세션(2차) 재실측 — KNOW-037 근거

| 검증 | 결과 |
|---|---|
| `node --version` | `v24.13.0` |
| `node --test slack-bot/tests/` (전체 출력 확인) | **exit 1** — `Error: Cannot find module '<abs>\slack-bot\tests'` · `code: 'MODULE_NOT_FOUND'` · tests 1 / pass 0 / fail 1 |
| `node --test "slack-bot/tests/*.test.js"` | **exit 0** — tests 60 / pass 60 / fail 0 · duration 29103ms |
| `git archive origin/main slack-bot \| tar -x -C <tmp>` 후 `node --test "slack-bot/tests/*.test.js"` | **exit 1** — `slack-bot/tests/dashboard.test.js:13` 의 `for (const dir of ['slack-bot','slack-bot-minimax'])` 때문에 형제 `slack-bot-minimax` 가 없어 MODULE_NOT_FOUND (부분 추출 결함) |
| `gh pr view 382 --json baseRefOid` | `2a2318d3fdd5015b2f631e05b99e01eadb5cd376` = PR #381 mergeCommit → 충돌 0건 근거 |
| `gh run view 41820079874` (main) | `completed/success` · headSha `e7d9b4e` |

## tPrivateKB 환류 (rule 55 §3)

**KNOW-037** — "Node 24 의 `node --test <디렉터리>` 는 거짓음성 — 이슈 verify 블록이 완료조건을 잘못 FAIL 로 만든다"

| 항목 | 값 |
|---|---|
| 노트 파일 | `.agent/k_layer/notes/KNOW-037_node24_test_directory_arg_false_negative_UNDETERMINED_verify_block.md` (2,288자) |
| tKB | **kbSn 6968** · csn 70424 · 제목 = 노트 파일명 · 본문 2,288자 **절단 없음** (`get` 으로 확인) |
| 중복 사전 조회 | `list --csn 70424 --search "node --test"` → 0건 · `"NEEDS_DECISION"` → 0건 (신규 사실) |
| 등록 경로 | `privatekb.py put` → `created kbSn=6968` → 제목 변경은 `KbUpdate` 로 (refType 은 갱신 경로에서 못 바꾼다 — 아래) |

**rule 55 §3 실측에서 새로 확인한 사실 2건 (같은 PR 에 함께 정정)**

1. **`list --search` 는 제목만 찾는다 — 본문은 검색 대상이 아니다.**
   실측: `node24`·`UNDETERMINED` (제목에 있음) → 1건 · `MODULE_NOT_FOUND`·`NEEDS_DECISION` (본문에만 있음) → **0건**.
   → 환류 제목(= k_layer 노트 파일명)에 **검색 키워드를 넣어야** "유사 질문이 바로 찾아진다"는 규칙 55 §3 의 목적이 산다.
   이에 KNOW-037 파일명 슬러그를 `node24_test_directory_arg_false_negative_UNDETERMINED_verify_block` 로 바꿨고,
   tKB 행 제목도 `KbUpdate` 로 같은 값으로 바꿨다(검색 5종으로 재확인).
2. **`put` 의 `--ref-type` 은 신규 생성에만 적용된다** — 갱신 경로(`KbUpdate`)는 title·content·tags 만 넘긴다.
   → 첫 등록을 `put`(기본 `GENERAL`) 으로 해서 refType 이 `KNOWLEDGE` 가 아닌 행이 되었다. `sync-klayer`(기본 `KNOWLEDGE`) 경로가 정본이다.
   → `scripts/privatekb/README.md` 에 **함정 6** 으로 추가했다(부수적으로 `KbUpdate` 경로가 title 은 바꾼다는 사실도 함께 기록).

## 이번 세션의 disposition — READY 유지 → REVIEW 로 에스컬레이션

4219 는 **연속 4사이클** 진행 없이 READY 에 머물렀다 — 즉 [C-보강] 의 "3회 이상 연속 defer" 에 해당한다.

| # | 시각(UTC) | 주체 | 내용 |
|---|---|---|---|
| 1 | 2026-11-04T02:58:26Z | watchdog | `[BUDGET]` 105분 예산 소진 — 처리하지 못함 |
| 2 | 2026-11-04T05:48:33Z | watchdog | `[BUDGET]` 105분 예산 소진 — 처리하지 못함 |
| 3 | 2026-11-04T07:49:34Z | gissue-agent | ③ 미충족(4221=REVIEW) — **READY 유지** |
| 4 | 2026-11-04T09:39:01Z | gissue-agent | ③ 미충족(4221=NEEDS_DECISION) — **READY 유지** |

→ 이번 세션은 "상태 재확인만 하는" 5번째 사이클을 만들지 않고 **실제 산출물(사양서 정정 + PR #382 머지 + 환류)** 을 만든 뒤,
**REVIEW 로 에스컬레이션**했다(사람 판단 대기). NEEDS_DECISION 이 아닌 REVIEW 인 이유:
남은 것은 ③(4221 DONE)이라는 **검증 항목**이며 4221 쪽의 §10-1 마스킹 결정만 사람이 해야 한다(rule 45 — "검증이 남았으면 REVIEW").



## 4221 이 아직 DONE 이 아닌 실측 근거 (4219 완료조건 ③)

4221 은 **NEEDS_DECISION** 이며(2026-11-04 08:05:43Z 전이), 남은 사유는 2가지다.

1. **완료조건 verify 블록의 구조적 결함** — 이슈 verify 블록 마지막 줄이 `node --test <디렉터리>` 인자형이다.
   Node v24.13.0 은 디렉터리 인자를 모듈로 로드해 `Cannot find module` 로 죽는다(위 실측 exit 1).
   글로브형(`*.test.js`)은 exit 0 · 60/60 pass다. → 감사 게이트(`review-done-audit`)가 "완료조건 verify 실행" 항목을
   **판정불가(C10)** 로 처리해 REVIEW → NEEDS_DECISION 전이가 났다.
   (4221 작업 기록의 "결함 A" 와 동일 — `git archive` 추출형이면 형제 `slack-bot-minimax` 참조 때문에 "결함 B" 도 함께 난다.)
2. **§10-1 마스킹 소급 여부 — 사용자 결정 대기.** (B) 구현은 신규 Jev 송신에만 `maskString` 을 적용했고
   기존 `classifyRequest` LLM 프롬프트·`callClaude` 경로에는 소급하지 않았다. 상위 이슈는 이 판단을 임의로 확정하지 않는다.

## 남은 것 (이번 세션이 하지 않은 것)

- **4220·4221·4222 의 구현 대행 금지** — 4219 는 수렴 판정만 한다. 4220/4221/4222 는 **읽기 전용 조회만** 했고 쓰기 0건이다.
- **4221 의 DONE 전이** — 4221 자신의 세션/사용자 결정 소관.
- **§10-1 마스킹 결정** — 사용자 판단 대기. 상위 이슈에서 확정하지 않는다.
- **D 재랜딩** — lowyworkenv PR #1101 로 이미 머지됨(2026-11-04T00:17:07Z). 이번 세션의 추가 조치 없음.

## 후속

1. **4221 의 verify 블록을 글로브형으로 정정** — `node --test "$T/slack-bot/tests/"` → `node --test "$T/slack-bot/tests/*.test.js"`
   (+ `git archive` 추출 시 형제 `slack-bot-minimax` 참조 결함 회피 — 저장소 전체를 추출하거나 형제까지 포함). 그러면 C10 이 판정 가능해져 4221 이 DONE 으로 갈 수 있다.
2. **4221 에 C10 증거 코멘트** — 글로브형 실행 결과(60/60 · exit 0)를 이슈에 남기고 사람/감사가 DONE 전이.
3. **§10-1 마스킹 소급 결정** — 사용자 판단.
4. **4221 이 DONE 이 되면** — `node scripts/gissue/verify-runner.mjs 4219 70424 --comment --json` 재실행(PASS 확인) 후 4219 DONE 전이.
   단 verify 블록은 ①② 만 검사하므로 **③ 은 4220/4221/4222 상태 재조회**로 별도 확인해야 한다.
5. **KNOW-037 재사용** — 이슈 완료조건에 `node --test` 를 쓸 때는 **디렉터리 인자 금지**(Node 24 거짓음성). 글로브/파일 인자 + 저장소 전체 추출.
