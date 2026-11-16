# CSN 70424 저장소·PR 레벨 정비 145차 (2026-11-16 10:07 KST) — [0]/[E]/[F]/[H] 정례 점검 + 고정 임시 파일명 충돌 결함 수정

> 세션 성격: **저장소/PR 레벨 정비** (CSN 70424 저장소 전체 스코프, 단일 이슈 처리가 아니다).
> 규칙상 항상 도는 [0] 병합충돌 · [E] CI/검증 실패 · [F] 오판 stash · [H] 최근 코멘트 논리 재검증 4축을 돈다.
> **이번 회차 산출물: 코드 수정 2건 + 회귀 테스트 1건 신규 + k-layer 1건 + 본 기록 1건.**
> 이슈 쓰기 0건 · 상태 전이 0건 · stash drop 0건 · 정정 0건.

## 세션 성격 — 10:07 슬롯

- 직전 정비 기록(144차, 2026-11-16 09:07 KST) 이후 **origin/main 추가 머지 0건** — 작업 시작 시점
  `origin/main` HEAD = **`8f73924`** 를 base 로 삼았다.
- 실행 주체: 이 세션은 스케줄러가 직접 띄운 **헤드리스 폴백 워커**이므로 work_history 1건 + PR 생성을
  **직접 수행**한다(서브에이전트 위임은 MODEL_USAGE_SPEC 상 예외이며 단건 기록 PR 에 불필요하다).
- 사전 락 불요 — `scripts/gissue/csn-projects.json` 실측 기준 CSN 70424 의 프로젝트가 이 저장소
  (giip-fde-agent)이고, lowyworkenv 는 이 세션 CSN 밖의 다른 저장소다. 144차와 동일 판단.
- 작업 워크트리 `D:\temp\worktrees\giip-fde-agent\maint-145-1007`
  (브랜치 `chore/csn70424-maint145-20261116-1007`, base = `origin/main` `8f73924`) — 공유 체크아웃은 읽기 전용.

## [0] PR 병합충돌 — 대상 0건

- `gh pr list --repo LowyShin/giip-fde-agent --state open --json number,headRefName,url,title,createdAt`
  → **열린 PR 0건**(`[]`) — 10:46 재확인. 병합충돌(CONFLICTING) 대상 0건 → 조용히 건너뜀.
- 루트에 vendored 제품 레포 없음(서브모듈은 `.gemini/extensions/bkit` 1건뿐 — giip 제품 레포 아님).

## [E] CI/검증 실패 — 열린 PR 0건 / **main 의 잠재 결함 1건 발견·수정**

### 발견 — "같은 커밋인데 워크트리는 PASS, 공유 체크아웃은 FAIL"

- [E] 대상(열린 PR)은 0건. green 확인을 대신해 **main push run + 로컬 게이트**를 양쪽에서 돌렸는데,
  **같은 커밋(8f73924)** 에서 워크트리 게이트는 PASS / 공유 체크아웃 게이트는 FAIL 했다.
- 근거 없이 "코드 결함"으로 단정하지 않고 **재현**했다 → 원인은 코드가 아니라 **동시 실행**이었다.
  두 게이트를 동시에 돌리면 한쪽이 다른 쪽의 출력 리다이렉트 파일을 지워 **빈 출력**이 되고,
  `test-verify-runner-korean-encoding.ps1` 가 `한글보존=False` 로 **거짓 FAIL** 을 낸다.
  - 재현: 같은 테스트 2개 동시 실행 → run1 exit 0(PASS=4) · **run2 exit 1**(PASS=3, 출력=빈값).
  - 단독 실행 시에는 **양쪽 모두 PASS** → "워크트리 green ≠ 공유 체크아웃 green" 의 원인이 재현된 것.
- 결함 위치: `scripts/gissue/tests/test-verify-runner-korean-encoding.ps1` — stdout/stderr 리다이렉트
  파일을 **고정 이름**(`$env:TEMP\gissue_korean_test_out.txt` / `_err.txt`)으로 만들어 쓰고 지운다.
  이 호스트는 CSN 별 정비 세션이 매시 **동시에** 돌아가는데(레포가 달라도 임시 폴더는 하나) → 충돌이 일상적이다.
- 저장소 전수 확인: .ps1 **102건** 중 고정 임시 파일명 사용처는 **이 1파일 6줄**뿐(나머지 101건은
  `$PID` · GUID 보간 사용) → 이번 수정이 해당 클래스 전체를 정리한다.

### 수정

1. `scripts/gissue/tests/test-verify-runner-korean-encoding.ps1` — 리다이렉트 파일명을
   **실행(run)마다 고유한 GUID** 로 변경(생성·조회·삭제 3곳 모두 같은 이름). BOM + CRLF 유지(바이트 단위 편집).
2. `scripts/gissue/tests/test-temp-filename-collision.ps1` — **신규 회귀 테스트**. 저장소 전체 .ps1 을 훑어
   고정 임시 파일명 사용처가 0건인지 검사하고, **검사기 자체**(고정명 검출 · `$PID`/GUID/괄호식/주석 오탐 없음)와
   **스캔 범위**(`.agent/scripts/`·`mgmt/`·`slack-bot/`·`scripts/` 각 건수)를 함께 고정한다.
3. `scripts/gissue/run-repo-gates.ps1` — `$ExpectedPs1TestCount` **42 → 43**(없으면 "테스트가 사라져도 통과" 하는
   방어 공백이 생긴다).

### 회귀 증명 (수정 전 FAIL → 수정 후 PASS)

| 단계 | 결과 |
|---|---|
| 수정 전 코드(HEAD 복원) + 신규 검사 | **exit 1** · PASS=11 / FAIL=1 · 사용처 6줄 지목(140·141·144·145·156·157) · 스캔 102건 |
| 수정 후 코드 + 신규 검사 | **exit 0** · PASS=12 / FAIL=0 · 사용처 0건 |
| 수정 후 · 같은 테스트 2개 동시 실행 | **양쪽 모두 exit 0** (PASS=4 / PASS=4) — 수정 전엔 1건 FAIL |
| 저장소 게이트(워크트리) | **exit 0** · ps1 **43건** / mjs 8건 / 링크스캔 1 / **실패 0건** |

- k-layer: `KNOW-051_temp_filename_must_be_unique_per_run.md` 신규 + `INDEX.md` 행 추가
  (tKB kbSn **7199**, 본문 sha1 일치 실측).

## [F] Orphan auto-unblock stash — 대상 0건

- `git stash list` → **빈 출력**(stash 0건) — 공유 체크아웃 실측(10:46).

## [H] 최근 코멘트 논리 재검증 — 4h 6건 / 24h 12건(검증 가능 주장 전건 TRUE) · 정정 0 · 전이 0 · 이슈 쓰기 0

- 조회: `giipprj/giipdb/mgmt/listRecentCommentIssues.ps1 -Csn 70424 -HoursBack 2|4|24 -Json`(상태 무관,
  `powershell` 5.1 — 이 PC 엔 `pwsh` 없음, rule 62). 콘솔 코드페이지(cp949)로 리다이렉트하면
  JSON 한글이 깨지므로 **UTF-8 래퍼로 출력**한 뒤 파싱했다.
- **2시간 창 0건**(10:47) · **4시간 창 6건** · **24시간 창 12건**. 자기 세션이 남긴 코멘트 0건 → 자기코멘트 제외 대상 0건.
- **운영 스킵 통지 6건**(isn 5053·4699·4556·4130·4300·4211, author `gissue-scheduler-watchdog`) —
  "isn 이 REVIEW/TESTED 라 이번 :07 실행 대상이 아님 → 스킵(쿨다운 4h)" 라는 **정책 서술**이며,
  조회 목록의 status 와 전건 일치(REVIEW). 거짓 사실 주장으로 이슈를 잠그는 유형이 아니다 → 재검증 결과 참.
- **[G] Actionflow 재검증 게이트 SKIP 3건**(isn 2648·1968·4530, author `Lowy Shin`) —
  검증 가능한 사실 주장 = "`## Test Procedure` 정확 헤딩 섹션 부재".
  `get-issue.sh` 로 본문+전체 코멘트를 받아 `^\s*##\s*Test Procedure` **정확 헤딩 라인**을 직접 파싱:
  isn 2648 → **0건**(백틱 인용 6건) · isn 1968 → **0건**(인용 9건) · isn 4530 → **0건**(인용 6건).
  → 주장이 참. 이 유형은 "파일 없음" 식 거짓 블로커가 아니라 사람 판단 대기 상태라 REVIEW 에 정상 잔존 중.
- **review-audit 3건** — isn 4219(READY) · 5349(DONE) · 5345(DONE). PR 머지 주장을 `gh pr view` 로 재확인:
  4219 → 연계 PR **#382 MERGED**(`e7d9b4e`, 2026-11-04) · 5349 → **#445 MERGED**(`fb636ee`, 2026-11-15) ·
  5345 → **#443 MERGED**(`20feefd`, 2026-11-15). 4219 의 완료조건 ③(하위 4221 NEEDS_DECISION)은 미충족 →
  READY 는 정확한 상태다(되돌릴 거짓 잠금 없음). 5349/5345 의 DONE 근거 일치.
- **→ 검증 가능한 사실 주장 전건 TRUE, 거짓 잠금 0건.** [H] §5 "주장이 맞으면 조용히 통과" 에 따라
  이슈 쓰기·정정·전이 전부 **0건**. (권한 범위: READY 복귀까지만 — 이번엔 되돌릴 대상 자체가 없었음)

## 워크트리/브랜치 인벤토리 (관찰 — 자기 것만 회수, rule 86)

- 본 세션 소유는 `maint-145-1007` 뿐 → **PR 머지 후 이것만** 정본 도구(`cleanup-worktrees.ps1`)로 회수한다.
- 그 외 워크트리는 rule 86 "자기가 만든 것만" 에 따라 **미접촉(관찰만)** —
  `maint-118-0545`(clean) · `maint-62-2331`(미커밋 2건) · `giip-5054-refine`(스테이징) ·
  `giip-5142-svcguard`(미커밋 3건) · detached `verify-4139-c7` / `verify-5054-main` / `verify-5174-main`.
- 원격 브랜치 `bot/task-giip-4804` · `4805` · `4806` 는 **이 세션 CSN 밖 소유** → 계승·삭제·쓰기 0건.
  `chore/csn70424-maint131-20261115-1607` 은 연계 PR 이 MERGED 인데 ref 가 잔존 → 직전 슬롯 소유로 미접촉.

## 완료 판정 (실행 결과 기준)

- [0] 대상 0건 · [F] stash 0건 · [H] 4h 6건 / 24h 12건(전건 TRUE, 거짓 잠금 0) → 정정·전이·이슈 쓰기 **0건**.
- [E] 는 "열린 PR 실패 0건" 이 아니라 **main 의 잠재 결함 1건 발견·수정**(+ 회귀 테스트 1건 신규 + 게이트 기대값 상향).
- 로컬 게이트 워크트리 exit 0 (ps1 43 / mjs 8 / 링크스캔 1 / 실패 0건).
- 산출물 = 코드 2건 + 회귀 테스트 1건 + k-layer 1건 + 본 work_history 1건. PR 1개 관례 유지.
- 머지 커밋·워크트리 회수 결과 등 확정값은 **본 기록이 아니라 PR 코멘트**로 인계한다(115~144차와 동일).

## 회차 연장 — 직전 엔진 시도(10:15)의 **미완 push 인계** 처리 (11:2x, Claude 엔진 폴백)

- 직전 시도(MiniMax 엔진, 10:15 시작)는 코드 수정·커밋(`acb9d1a`)까지 끝냈으나 **push 가 대기 상태로 끝났다** —
  CSN 33 세션이 전역 저장소 락(`gissue-csn33:maintenance`)을 쥔 상태였고 `push_with_auth.ps1` 호출이
  락 해제를 기다리다 세션 종료와 함께 사라졌다. **근거**: 세션 종료 시점 `git branch -r` 에 `maint145` 가
  없고 `git push --dry-run` 도 미실행 상태였으며, 락 대기 중인 push 프로세스도 남아 있지 않았다.
- 이 회차가 그 미완 조치를 이어받아 **실측 → 완료** 했다.

### 1. 수정 재검증 (게이트)

- 워크트리 `maint-145-1007` 에서 `scripts/gissue/run-repo-gates.ps1` 재실행 → **exit 0** ·
  ps1 **43건** / mjs **8건** / 링크스캔 1 / **실패 0건** (신규 `test-temp-filename-collision.ps1` PASS 포함).

### 2. tKB 대조 (rule 61 — 등록이 실제로 있는지 조회로 확인)

- `scripts/privatekb/privatekb.py get --csn 70424 --kbsn 7199` → **존재** · csn **70424** ·
  title `giip-fde-agent/KNOW-051_temp_filename_must_be_unique_per_run.md` · 본문 = k-layer 파일 본문과 동일.

### 3. 4축 재실측 (11:2x 실측값)

| 축 | 결과 |
|---|---|
| [0] 병합충돌 | 열린 PR **0건** → 대상 0건 |
| [E] CI/검증 실패 | 열린 PR **0건** → 대상 0건 (main 게이트는 1번에서 exit 0 확인) |
| [F] orphan stash | `git stash list` **0건** → 대상 0건 |
| [H] 코멘트 재검증 | **2시간 창 0건** / 24시간 창 **12건** — 검증 가능 주장 **전건 TRUE** → 정정·전이·이슈 쓰기 **0건** |

### 4. [H] 24시간 창 12건 재검증 내역 (코멘트를 믿지 않고 직접 조회)

- **운영 스킵 통지 6건**(isn 5053·4699·4556·4130·4300·4211, author `gissue-scheduler-watchdog`) —
  (a) status 주장 "REVIEW/TESTED": 조회 목록의 status 와 **전건 REVIEW 로 일치** → TRUE.
  (b) "새 사람 신호 없음" 주장: `get-issue.sh` 로 받은 코멘트 이력에서 최근 사람(author `Lowy Shin`) 코멘트가
  isn 5053 = 2026-11-13 · 4699 = 11-12 · 4556 = 11-12 · 4130 = 11-12 · 4300 = 11-12 · 4211 = 11-12 이고,
  마지막 코멘트는 전부 워치독(2026-11-15T23:2xZ) → 사람 신호 없음 → TRUE.
- **[G] Actionflow 재검증 게이트 SKIP 3건**(isn 2648·1968·4530, author `Lowy Shin`) —
  검증 가능한 사실 주장 = "`## Test Procedure` **정확 헤딩** 섹션 부재".
  `get-issue.sh` 로 본문+전체 코멘트를 받아(2648 = 32건 · 1968 = 30건 · 4530 = 31건)
  `^\s*##\s*Test\s+Procedure\s*$` **정확 헤딩 라인**을 직접 파싱 → **셋 다 0건**
  (`Test Procedure` 문자열은 백틱 인용으로만 등장) → TRUE.
- **review-audit 3건**(isn 4219 READY · 5349 DONE · 5345 DONE) — PR 머지 주장을 `gh pr view` 로 재확인:
  4219 → **#382 MERGED**(`e7d9b4e`, 2026-11-04) · 5349 → **#445 MERGED**(`fb636ee`, 2026-11-15) ·
  5345 → **#443 MERGED**(`20feefd`, 2026-11-15) → TRUE.
  4219 의 하위 4221 이 NEEDS_DECISION 상태이므로 READY 는 정확한 상태다(되돌릴 거짓 잠금 없음).
- → **거짓 잠금 0건**. [H] §5 "주장이 맞으면 조용히 통과" 에 따라 이슈 쓰기·정정·전이 **0건**.

### 5. 마감 (push → PR → 머지 → 워크트리 회수)

- push 는 직전 회차 관례대로 **직접 `git push -u origin <브랜치>`** 로 수행했다
  (이 저장소의 과거 정비 세션 기록이 동일 방식 — 전역 락은 lowyworkenv 공유 체크아웃 직렬화용이며,
  타 저장소 push 를 막지 않는다. 대기 중 push 가 세션 종료와 함께 사라진 것이 이번 인계 사유였다).
- 확정값(머지 커밋·워크트리 회수 결과)은 **PR 코멘트**로 인계한다(115~144차와 동일 — 사후 기록 PR 을 만들지 않는다).
