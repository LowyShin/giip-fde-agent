# 이슈 번호 지정 실행 `-OnlyIsn` — AI 인스턴스용 유저가이드 (giip 5544)

> **독자: 스케줄러가 도는 호스트의 AI 에이전트, 또는 이슈 처리를 트리거하는 감지기/세션의 AI.**
> 특정 이슈 1건을 정기 큐를 기다리지 않고 즉시 처리시켜야 할 때, 이 문서의 규칙대로
> `run-gissue-claude.ps1 -OnlyIsn <isn>` 을 호출하고 그 결과를 해석한다.
> 사양의 정본은 [`hourly-issue-scheduler.md`](hourly-issue-scheduler.md) §18이며, 이 문서는
> 그 위의 **사용법**이다 — 동작이 이 문서와 사양서·코드와 다르면 사양서와 코드가 이긴다.
> 판정 코드의 정본: `scripts/gissue/lib/only-isn.ps1`. 이슈: **giip 5544**.

---

## 0. 이 기능이 하는 일 (한 줄)

`-OnlyIsn <isn>` 은 러너의 큐를 지정 이슈 1건으로 교체해 즉시 처리시키는 파라미터다. **큐 우선순위와 READY 경과(기본 60분) 조건만 우회**하고, 안전 게이트는 전부 그대로다. 게이트에 걸리면 실행되지 않고 사유가 로그와 이슈 코멘트로 남는다 — "지정하면 무조건 돈다"가 아니다.

## 1. 써도 되는 경우 / 쓰면 안 되는 경우

**써도 되는 경우**
- 사람이 "이 이슈 지금 처리해"라고 명시적으로 지시했다.
- 감지기(폴링)가 새 처리 대상 이슈를 발견했고, 그 감지기의 설계가 "발견 즉시 트리거"로 승인돼 있다.
- 정기 실행에서 밀린 특정 이슈를 운영 판단으로 앞당긴다.

**쓰면 안 되는 경우**
- 여러 이슈를 빨리 처리하고 싶을 때 반복 호출하는 용도 — 그건 큐 우선순위의 일이다. 1회 호출 = 1건만 처리된다.
- NEEDS_DECISION 이슈를 "일단 돌려보자"로 지정 — 게이트가 막고, 반복 지정해도 결과는 같다. 사람의 결정이 먼저다.
- 다른 실행이 처리 중인 이슈를 재촉하는 용도 — `IN_PROGRESS_ACTIVE`로 거부된다. 끝날 때까지 기다려라.
- 대상 CSN을 모른 채 남의 CSN 이슈일 수 있는 번호를 지정 — 소속 검증에 걸려 실행되지 않는다. 먼저 이슈의 소속 CSN을 확인하라.

## 2. 호출 방법

```powershell
# 기본형: 소속 CSN을 알 때 (권장 — 기동 범위가 좁다)
powershell.exe -File "<REPO_ROOT>/scripts/gissue/run-gissue-claude.ps1" -OnlyCsn <csn> -OnlyIsn <isn>

# CSN을 모를 때: 매핑된 전 CSN 중 이슈가 보이는 CSN만 기동된다
powershell.exe -File "<REPO_ROOT>/scripts/gissue/run-gissue-claude.ps1" -OnlyIsn <isn>

# 판정만 확인 (실행하지 않음 — 처음 쓰는 인스턴스는 이것부터)
powershell.exe -File "<REPO_ROOT>/scripts/gissue/run-gissue-claude.ps1" -DryRun -OnlyCsn <csn> -OnlyIsn <isn>
```

- `<REPO_ROOT>`는 그 호스트의 giip-fde-agent 정본 체크아웃이다. 호스트 로컬 사본(복사본)에서 돌리면 self-pull 대상이 아니어서 구버전 동작을 할 수 있다 — 반드시 정본 체크아웃에서 실행하라(사양서 §17-5, §11).
- 정기 실행과 같은 CSN lock을 쓴다. 정기 실행이 도는 중이면 지정 실행이 대기하거나, 지정 이슈가 이미 처리 중으로 보여 거부될 수 있다 — 오류가 아니라 경합 규칙이다.

## 3. 결과 해석 — 호출한 AI가 할 일

실행 로그(잡 출력)와 이슈 코멘트에서 아래 표식으로 판정을 확인한다. **호출이 끝났다고 처리된 것이 아니다** — 반드시 표식을 확인하고, 확인한 판정을 지시한 사람/세션에게 보고하라.

| 표식 | 의미 | 호출한 AI의 대응 |
|---|---|---|
| `[ONLYISN] isn=<n> 지정 실행` + 이후 `[ISSUE] isn=<n> … 처리 시작` | 지정이 받아들여져 엔진 처리가 시작됨 | 처리 완료가 아니다. 이슈의 상태 전이·코멘트로 최종 결과를 확인해 보고하라 |
| `[ONLYISN-SKIP] reason=NEEDS_DECISION` | 사람 결정 대기라 실행 안 됨 | 재지정하지 마라. 결정이 필요한 항목임을 지시자에게 보고하라 |
| `[ONLYISN-SKIP] reason=IN_PROGRESS_ACTIVE` | 다른 실행이 처리 중 | 재지정하지 말고 기다려라. 60분 이상 정체하면 정기 실행이 회수한다 |
| `[ONLYISN-SKIP] reason=CSN_MISMATCH` 또는 Phase 1의 `소속 불일치` | 그 CSN의 이슈가 아님 | 소속 CSN을 확인해 올바른 `-OnlyCsn`으로 1회만 다시 지정하라 |
| `[ONLYISN-SKIP] reason=NOT_FOUND` | 대상 CSN 범위에서 못 찾음 | 번호가 맞는지, 소속 CSN이 매핑에 있는지 확인하라. 무작정 전 CSN에 반복 지정하지 마라 |
| `[ONLYISN-SKIP] reason=AUTO_OPS` | 자동 감지 기록이라 작업 대상 아님 | 정상 판정이다. 감지 이슈는 liveness 경로가 닫는다 — 지정 실행으로 건드리지 마라 |
| `[ONLYISN-SKIP] reason=REVIEW_NO_NEW_SIGNAL` | REVIEW/TESTED 재검증 큐 제외 상태 | 새 신호(사람 코멘트 등)가 생긴 뒤에나 의미가 있다. 반복 지정으로 우회되지 않는다 |
| `[ONLYISN-SKIP] reason=STATUS_NOT_PROCESSABLE` | DONE 등 처리 대상 상태가 아님 | 이미 끝난 이슈다. 지시자에게 그 사실을 보고하라 |
| `[ONLYISN-SKIP] reason=LOOKUP_ERROR` | 조회 자체가 실패(네트워크·인증 등) | 인프라 문제다. 시간을 두고 1회 재시도하고, 반복되면 운영 항목으로 보고하라 |
| 로그에 `[REVIEW-SKIP]`/`[REVIEW-CAP]` (지정 실행 뒤) | 쿨다운·회차 상한 게이트가 건너뜀 | 지정 실행으로도 쿨다운은 우회되지 않는 것이 사양이다. 쿨다운(기본 4시간) 뒤 정기 실행이 처리한다 |

## 4. 감지기(폴링)가 붙는 경우의 규칙

5분 간격 감지기가 발견 즉시 `-OnlyIsn`을 호출하는 구성이 대표 용도다. 감지기 쪽 AI/스크립트는 아래를 지켜야 한다.

1. **중복 트리거 방지**: 같은 isn을 이미 트리거했으면 다시 호출하지 않는다. 감지기 자신의 상태 파일에 트리거한 isn과 시각을 남기고, 이슈가 IN_PROGRESS/REVIEW 등으로 전이된 뒤에는 트리거 대상에서 뺀다. 러너의 `IN_PROGRESS_ACTIVE` 거부는 최후의 방어선이지 중복 방지책이 아니다.
2. **처리 대상 판정은 감지기가, 게이트 판정은 러너가**: 감지기는 "처리할 이슈인가"(예: 자기 CSN의 PENDING·READY)만 보고 지정한다. NEEDS_DECISION 같은 게이트는 러너가 막는다 — 감지기가 게이트를 흉내 내어 자체 판정으로 건너뛰거나 강제하지 마라.
3. **SKIP은 실패가 아니다**: `[ONLYISN-SKIP]`은 "게이트가 일한 결과"다. 감지기는 SKIP 사유를 기록하고, `NEEDS_DECISION`이면 사람에게 올리고, `IN_PROGRESS_ACTIVE`면 다음 폴링에서 상태만 확인한다. 같은 isn에 대한 재트리거는 상태가 바뀐 뒤에만 한다.
4. **실행 이력으로 대조**: 지정 실행은 tKVS `scheduler_run_history`에 `trigger='onlyisn'`, `onlyIsn=<n>`으로 남는다(사양서 §18-6). "트리거했는데 돌았는가"는 이 이력과 이슈 코멘트로 확인하라 — 감지기의 자체 로그만으로 단정하지 마라.

## 5. 금지 사항

- ❌ 게이트를 우회하려고 이슈 상태를 임의로 바꾸거나(예: NEEDS_DECISION을 READY로 되돌리기) 제목을 고쳐서 지정하기.
- ❌ `[OPS]` 자동 감지 이슈를 지정 실행으로 처리하기.
- ❌ SKIP된 isn을 사유가 해소되지 않았는데 반복 지정하기 (특히 NEEDS_DECISION·IN_PROGRESS_ACTIVE).
- ❌ 호스트 로컬 복사본 러너에 같은 기능을 따로 구현하기 — 기능은 정본에만 있고, 인스턴스는 self-pull로 받는다.
- ❌ 한 번의 호출로 여러 이슈가 처리될 것으로 기대하거나 보고하기.

## 6. 자주 묻는 것

- **지정하면 정기 실행(:07)은 어떻게 되나** — 영향 없다. 지정 실행은 별도 1회 실행이고, 정기 실행은 자기 큐대로 계속 돈다. 같은 이슈가 정기 큐에도 있으면 먼저 처리한 쪽이 상태를 전이시키고, 다른 쪽은 게이트(상태·IN_PROGRESS)로 자연히 걸러진다.
- **READY가 된 지 5분 된 이슈를 지정하면 바로 도나** — 그렇다. 그게 이 기능의 목적이다(경과 조건 우회). 단 PENDING은 원래 경과 조건이 없어 지정 없이도 다음 정기 실행에서 정제된다.
- **REVIEW를 지정하면 쿨다운을 건너뛰나** — 아니다. 쿨다운·상한은 잡 루프 게이트가 그대로 판정한다(§3 표의 `[REVIEW-SKIP]` 행).
- **지정 실행이 실제로 돌았는지 사후에 확인하려면** — ① 그 이슈의 코멘트(처리 시작·전이 기록) ② 실행 로그의 `[ONLYISN]` 표식 ③ tKVS `scheduler_run_history`의 `trigger='onlyisn'` 기록. 셋이 정본이다.

## 7. 관련 문서

- 사양 정본: [`hourly-issue-scheduler.md`](hourly-issue-scheduler.md) §18 (요약은 같은 문서 §3)
- 판정·조회 코드: `scripts/gissue/lib/only-isn.ps1` / 회귀 테스트: `scripts/gissue/tests/test-only-isn.ps1`
- 실행 이력 기록 방식: [`gissue-scheduler-run-history.md`](gissue-scheduler-run-history.md), 사양서 §17(tKVS 기록)
