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

## 변경 내용 (3파일)

| 파일 | 변경 |
|---|---|
| `slack-bot/docs/INTENT_ROUTING_JEV_SPEC.md` | §9 대응표에 **서브 이슈 열**(giip 4220/4221/4222 + 4219 링크)과 **상태 열** 추가 · (A)(B)(C)(D) 상태 단락을 실측값으로 교체 · (B) 에 남은 2건(verify 블록 Node 24 거짓음성 · §10-1 마스킹 소급 사용자 결정) 기재 · §10-2 정확도 서술을 (C) 결과 반영으로 갱신 · 헤더 "갱신" 이력에 §9·§10-2 반영 표기 |
| `docs/WHATS_NEW.md` | rule 36 — 이번 변경 항목 추가(기준일 `2026-11-04` 는 이미 동일) |
| `.agent/work_history/20261104_2006_csn70424_giip-4219-jev-spec-status-sync.md` | 신규 — 이 기록 |

**별도 커밋 1건(rule 54 자가 검사에서 발견한 사전 위반 즉시 정정)** — `docs/WHATS_NEW.md` 의 저장소 위생 정비 83·84·85차 항목에
남아 있던 **다른 CSN 번호와 고객 프로젝트 식별자 3건**을 `<csn>` 플레이스홀더로 치환했다.
이 저장소 자신의 CSN(70424) 은 rule 54 예외 대상이라 그대로 둔다. 이 건은 4219 의 의뢰와 무관하므로 **별도 커밋**으로 분리했다.

**§10-2 는 "정확도 미확인" 을 지우지 않았다.** (C) 결과는 38건 코퍼스 기준이므로 **범용 한국어·일본어 정확도는 미확인** 이라는 결론을 유지하고,
측정된 범위(92.1% · Jev 라우팅 13건 오류 0 · engine `jev-1.14.0`)와 미확인 범위를 나란히 적었다.

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
   (+ `git archive` 추출 시 형제 `slack-bot-minimax` 참조 결함 회피). 그러면 C10 이 판정 가능해져 4221 이 DONE 으로 갈 수 있다.
2. **4221 에 C10 증거 코멘트** — 글로브형 실행 결과(60/60 · exit 0)를 이슈에 남기고 사람/감사가 DONE 전이.
3. **§10-1 마스킹 소급 결정** — 사용자 판단.
4. **4221 이 DONE 이 되면** — `node scripts/gissue/verify-runner.mjs 4219 70424 --comment --json` 재실행(PASS 확인) 후 4219 DONE 전이.
   단 verify 블록은 ①② 만 검사하므로 **③ 은 4220/4221/4222 상태 재조회**로 별도 확인해야 한다.
