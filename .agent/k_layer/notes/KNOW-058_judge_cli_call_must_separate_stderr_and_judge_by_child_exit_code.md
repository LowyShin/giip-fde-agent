# KNOW-058 — 판정 LLM 호출은 stderr 를 stdout 에 합치지 말고 자식 종료코드로 판정한다 (PS 5.1 에서 stderr 한 줄이 종료성 오류가 된다)

> 근거: giip 6459 (2026-11-27 실측) · 발행: 2026-11-27 · 상태: 검증됨(직접 실측 + 회귀 테스트 고정)
>
> 관련 파일: 판정 엔진 `scripts/gissue/gissue-audit-lib.ps1` · 실행기 `scripts/gissue/lib/bounded-process.ps1`
> · 회귀 테스트 `scripts/gissue/tests/test-checklist-judge-stderr.ps1`
> · 관련: [KNOW-055](KNOW-055_process_exitcode_needs_handle_cached_or_it_reads_zero.md)(종료 코드는 핸들 캐시 없으면 항상 0) ·
> [KNOW-016](KNOW-016_revert_decision_unit_is_request_checklist_not_pr_presence.md)(판정 단위는 PR 유무가 아니라 의뢰 항목) ·
> [KNOW-036](KNOW-036_canonical_and_ported_gate_logic_drift_must_be_diffed_per_file.md)(정본·이식본 드리프트)

## 요지

**네이티브 CLI 를 부르는 판정 호출**이 `$prompt | & cli ... 2>&1` 형태면, Windows PowerShell 5.1 에서
**자식이 stderr 에 한 줄만 써도** 그 줄이 `NativeCommandError`(ErrorRecord)로 승격해 **종료성** 오류가 된다.
호출자 스코프가 `$ErrorActionPreference='Stop'` 이면 함수의 catch 가 `exit=-1` 을 돌려주고, 그 결과는
`ok=$false` → `Decision='HOLD'` 다. 즉 **리다이렉트 의도와 무관하게, stderr 가 존재한다는 사실 자체가
판정을 죽인다.**

여기에 두 결함이 더 얹힌다 — 라우터가 `--model` 을 honor 하지 않아 응답 형식이 안 맞아 파싱 0건이 되고,
타임아웃이 없어 무한 대기한다. 셋이 겹치면 판정은 **매 회차** HOLD 로 죽는다.

## 실측 (2026-11-27)

| | 관측 | 판정 |
|---|---|---|
| 자식이 stderr 에 쓰고 종료 0 | 예외로 죽음 → `exit=-1` | ✗ **판정 실패** |
| 자식이 stderr 에 쓰고 종료 1 | 같은 경로로 `exit=-1` | ✗ 종료 코드가 **사라짐** |
| 자식이 멈춤(무한 대기) | 9분+ 무응답 | ✗ 자원이 회수되지 않음 |
| stderr 를 stdout 에 합친 호출 | PS 5.1 이 stderr 한 줄을 `NativeCommandError` 로 승격 | ✗ 근본 |

실측된 CLI 는 `ANTHROPIC_API_KEY` 가 설정된 환경에서 "connectors are disabled because ... takes precedence
over your ... login" 경고를 **stderr 에 항상** 찍는다. gair 경유처럼 인증을 심어 건 뒤 호출하는 판정은
**환경이 설정되는 한 매 회차** 이 상태에 걸린다.

## 조치 (정본 수법)

1. **stdout/stderr 분리** — `2>&1` 를 제거하고 `lib/bounded-process.ps1`(Start-Process + 파일)로 부른다.
   성공/실패는 stderr 유무가 아니라 **자식의 실제 종료코드**로 판정한다. stderr 는 **진단 사유 전용**
   (판정 본문 아님) — 300자 절단 + `sk-…`·`x-functions-key`·`API_KEY`·`Bearer` 마스킹.
2. **유한 대기** — `Invoke-GissueBoundedProcess` 에 **선택** `-StandardInputFile`(기본 `$null` = 기존 호출자
   불변), `Resolve-GissueBoundedCallTimeoutSec` 에 `Kind 'Claude'`(env `GISSUE_CLAUDE_CALL_TIMEOUT_SEC`,
   기본 **300초**). 타임아웃은 **실패**다(`ok=$false`, `timedout=1`) — 성공으로 취급하지 않는다.
3. **프롬프트는 stdin 으로** — UTF-8 **BOM 없는** 임시 파일로 써서 넘긴다(종전 파이프 경로는 코드페이지에
   종속돼 한글이 깨질 수 있었다).
4. **형식 불일치 폴백 1회** — 응답을 받았는데 기대 형식(`ITEM|`) 줄이 0건이면, 인증 env 를 비운 상태로
   직접 경로를 **1회** 재호출한다. 폴백도 0건이면 **HOLD 유지** — 실패를 성공으로 뒤집지 않는다.
5. **실패 사유에 진단 요소** — 사유 문자열에 **종료코드 · 경로(`gair`/`direct`/`gair-fallback-direct`) ·
   stderr 요약**을 반드시 넣는다. 사유는 로그와 감사 코멘트에 남으므로 사람이 로그만 보고 원인을 알 수 있어야 한다.

## 규칙 (다음 세션이 지킬 것)

1. **네이티브 stderr 를 stdout 에 합치지 않는다** — 합쳐야 할 정보가 있으면 **자식 종료코드**로 판정하고
   stderr 는 진단 사유로만 쓴다. `2>&1` 패턴이 남아 있으면 그 호출은 "stderr 한 줄에 죽는" 상태로 본다.
2. **판정 호출에는 유한 대기가 있어야 한다** — 무한 대기는 스윕 전체를 붙잡는다. 한도 초과는 **실패**로
   표면화하고(`timedout=1`), 실패를 성공으로 바꾸지 않는다.
3. **실패 사유에 종료코드·경로·stderr 요약을 남긴다** — `exit=<n>` 만 남기면 원인 진단이 불가능하다.
   이유는 로그/코멘트만으로 재구성 가능해야 한다.
4. **폴백은 1회이고, 폴백 실패도 실패다** — 형식 불일치 때 재시도하되 무한 재시도 금지. 폴백 경로의 표기가
   다르면(예: `gair-fallback-direct`) 사유에서 구분 가능해야 한다.
5. **정본·이식본 양쪽에 같은 수법을 적용한다** — 한쪽만 고치면 또 다른 단방향 드리프트가 된다. 이식본에
   이미 수리가 있으면 **역반영(back-port)** 으로 정본에 옮기고, 정본에 이미 있으면 그쪽을 고친다.

## 회귀 테스트

`scripts/gissue/tests/test-checklist-judge-stderr.ps1` — LLM/네트워크 미사용, 환경 비의존, **가짜 CLI 스텁**
(임시 `.cmd` 를 `env GISSUE_CLAUDE_EXE` 로 주입). 고정 항목:

① stderr+exit 0 → **성공**(종전엔 exit=-1 로 죽었다) · stderr 가 판정 본문에 섞이지 않음
② stderr+exit 1 → **실패** + 예외로 죽지 않음 · 실제 종료 코드가 보고됨
③ 실패 사유에 `exit=`·`route=`·stderr 요약 존재
④ 멈춘 자식 → 유한 대기 후 **실패** + `timedout=1` (타임아웃을 성공으로 보지 않음)
⑤ 프롬프트가 자식 stdin 으로 전달됨 (한글까지 바이트 그대로)
⑥ gair 응답 형식 불일치(0건) → 직접 경로 **1회** 폴백하고 폴백 응답으로 판정 성공
⑦ 폴백까지 0건이면 **HOLD 유지** (실패를 성공으로 뒤집지 않음)
