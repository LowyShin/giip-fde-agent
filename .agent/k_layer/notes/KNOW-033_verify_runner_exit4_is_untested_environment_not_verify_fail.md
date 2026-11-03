# KNOW-033 — verify-runner 종료코드 4 는 "검증 실패" 가 아니라 "검증 미실행" 이다

> 근거: 2026-11-04 저장소 정비 92차 세션 실측 (work_history 20261104_0630) · 발행: 2026-11-04 · 상태: 검증됨(실측)

## 요지

`verify-runner.mjs` 는 verify 블록을 실행하기 **전에** 체크아웃 상태 게이트(giip 2925)를 통과해야 한다.
게이트는 **이슈의 CSN 으로 `csn-projects.json` 에서 찾은 workdir** 를 대상으로 세 가지를 확인한다 —
① 현재 브랜치 == 기본 브랜치 ② `HEAD == origin/<기본브랜치>` ③ `git status --porcelain` 이 빈 상태.

셋 중 하나라도 어긋나면 **verify 블록을 아예 실행하지 않고 종료코드 4**(`INVALID_ENVIRONMENT`)로 끝낸다.
반면 **종료코드 1 은 "verify 블록이 실행된 뒤 실패"** 다. 둘은 전혀 다른 사실이다.

→ [H] 재검증에서 기존 코멘트의 "verify-runner 결과는 FAIL(exit 1)" 이라는 주장을 재현하려 할 때,
**공유 체크아웃이 기본 브랜치와 1커밋이라도 뒤처져 있으면 재현 결과는 exit 4 가 되고, 그 자체는 주장을 반박하지 않는다.**
먼저 공유 체크아웃을 ff-sync 한 뒤 재실행해야 진짜 판정(exit 1 / exit 0)을 얻는다.

## 사례 (2026-11-04 저장소 정비 92차)

재검증 대상 이슈의 마지막 코멘트(giip 4219)가 다음 두 가지를 **함께** 주장하고 있었다.

- "완료조건 ② 미충족 — `git show origin/main:MODEL_USAGE_SPEC.md | grep -qi 'jev'` → **exit 1**"
- "현재 `node scripts/gissue/verify-runner.mjs 4219 70424` 의 결과는 **FAIL(exit 1)** — 완료조건 2 가 실패한다"

92차가 그대로 재실행한 결과는 **exit 4** 였다.

```
[CHECKOUT-GATE] 검증 환경 부적격 — verify 블록을 실행하지 않습니다.

HEAD(60d09f9) !== origin/main(6fe4a0b) — 기본 브랜치와 동기화되지 않음
```

원인은 **명령이 잘못된 게 아니라 환경이 어긋나 있던 것**이었다 — 공유 체크아웃이 1커밋 뒤처져 있었다.
`git merge --ff-only origin/main` 으로 ff-sync 한 뒤 재실행하니 **exit 1** 이 나와 코멘트의 주장과 일치했다.

게이트 코드를 직접 읽어 확인한 판정 조건(`scripts/gissue/verify-runner.mjs`):

| 위치 | 조건 | 실패 시 |
|---|---|---|
| `getWorkdirFromCsn` | `csn-projects.json` 의 `csn.<csn>.workdir` | workdir 를 못 찾으면 게이트 자체를 건너뜀 |
| `checkCheckoutState` ① | `rev-parse --abbrev-ref HEAD` == 기본 브랜치 | exit 4 |
| `checkCheckoutState` ② | `rev-parse HEAD` == `rev-parse origin/<기본브랜치>` | exit 4 |
| `checkCheckoutState` ③ | `status --porcelain` 이 빈 문자열 | exit 4 |

기본 브랜치는 `git symbolic-ref refs/remotes/origin/HEAD` 로 판정하고, 실패 시 `main` 으로 폴백한다.

## 판정 규칙

1. **exit 4 와 exit 1 을 같은 "실패" 로 취급하지 않는다.**
   exit 4 = 검증 **미실행**(환경 부적격) · exit 1 = 검증 실행 후 **실패**.
2. **[H] 재검증에서 verify-runner 결과를 근거로 삼은 기존 주장을 확인하려면, 먼저 해당 CSN 의 공유 체크아웃을
   기본 브랜치에 ff-sync 하고 working tree 가 깨끗한지 확인한다.** 게이트는 `status --porcelain` 도 본다 —
   워크트리 잔재만 있어도 exit 4 다.
3. **exit 4 를 받고 곧바로 "주장이 틀렸다" 로 정정하지 않는다.** 정정 코멘트는 실제 판정(exit 1 / exit 0)을
   확보한 뒤에만 한다. [H] 정정 규칙("주장이 맞으면 아무 것도 하지 않는다") 과 정면으로 어긋난다.
4. 게이트 사유는 러너가 그대로 출력한다(`[CHECKOUT-GATE] ... HEAD(x) !== origin/main(y)`) —
   무엇이 어긋났는지가 메시지에 적혀 있으므로 추측하지 말고 그 줄을 읽는다.

## 적용

- [H] 최근 코멘트 논리 재검증에서 verify-runner 실행 결과를 근거로 삼을 때.
- 이슈 완료조건에 verify 블록이 들어간 경우, 러너를 돌리기 전에 `csn-projects.json` 의 workdir 동기화 상태를 본다.
- 공유 체크아웃 ff-sync 는 **커밋·스테이징이 없는 읽기 전용 성격의 act** 다(다른 세션의 미커밋 변경이
  커밋에 섞일 위험이 없으므로) — 워크트리 격리를 굳이 만들지 않는다.
- 반대로 **이 저장소에 커밋할 때는** 공유 체크아웃을 쓰지 않고 전용 워크트리를 쓴다(다른 세션 분기 오염 방지).

## 관련

- `KNOW-013` — 회차 기록의 "완료" 서술은 실행되지 않은 계획일 수 있다
- `KNOW-022` — PR 머지는 이슈 측 쓰기(정정 코멘트·상태 전이) 실행의 증거가 아니다
- `KNOW-023` — 죽은 세션 워크트리의 미커밋 diff 는 main 보다 오래됐을 수 있다
- `KNOW-032` — 러너 105분 자기 마감이 커밋 단계를 자른다(커밋·push 를 기록 작성보다 먼저)
- 작업 기록: `.agent/work_history/20261104_0630_csn70424_repo-maintenance.md`
