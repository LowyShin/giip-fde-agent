# CSN 70424 저장소·PR 레벨 정비 112차 (2026-11-13 16:25 KST)

> 세션 성격: **저장소/PR 레벨 정비**(CSN 70424 저장소 전체 스코프) — 단일 이슈 처리가 아니다.
> 규칙상 항상 도는 [0] 병합충돌 · [E] CI/검증 실패 · [F] 오판 stash · [H] 최근 코멘트 논리 재검증
> 4축을 돌고, **워크트리 인벤토리·회수**를 수행했다.
> **코드 변경 0건 · 이슈 쓰기 1건([H] 정정 1건) · 상태 전이 0건.**

## 착수 상태 점검

- 공유 체크아웃 `C:\Users\lowys\Downloads\projects\giip-fde-agent` — 세션 시작 시 로컬 `main` = `origin/main` = `8edeb03`
  (111차 PR #415 머지본)로 **이미 동기 상태**였다 ⇒ ff-sync 불요(`git rev-parse HEAD origin/main` 동일 확인).
  **이후 공유 체크아웃은 읽기 전용**으로만 썼다(커밋·스테이징 0건).
- 작업 워크트리 `D:\temp\worktrees\giip-fde-agent\maint-112-1625`
  (브랜치 `chore/csn70424-maint112-20261113-1625`, base = `origin/main` `8edeb03`).
  **머지된 브랜치를 재사용하지 않고** `origin/main` 에서 새로 분기했다.
- 사전 락 불요 — 이 저장소는 CSN 70424 소관이고 lowyworkenv 자신은 다른 CSN 매핑이다
  (`scripts/gissue/csn-projects.json` 실측: csn 70424 → giip-fde-agent).
  프롬프트의 "대상 저장소가 lowyworkenv 자신의 CSN 일 때만 락" 조건 = **false** ⇒ 락 미획득·미해제.
- 공유 체크아웃 미커밋 잔재 untracked 3건(`.tmp-gissue-5054-test.md` · `.tmp-gissue-5054-usertest.md` ·
  `.tmp-gissue-5054-verify.md`)은 다른 이슈 세션의 코멘트 본문 임시 파일이다
  ⇒ **타 세션 산출물이라 삭제·스테이징하지 않았다**(정비 세션은 남의 미커밋 변경을 손대지 않는다).

## [0] PR merge conflict — 대상 0건

- `gh api "repos/LowyShin/giip-fde-agent/pulls?state=open&per_page=100"` → **0건**
  ⇒ 병합충돌 대상 0건 · 조치 0건. (GraphQL 레이트리밋 회피 목적 REST 조회)
- nested 관리 대상 레포 0건 — 이 저장소엔 nested 제품 레포가 없고, 서브모듈은 외부 벤더(`.gemini/extensions/bkit`) 하나뿐이다.
- 원격 ref = `main` + orphan 3건 `bot/task-giip-4804/4805/4806`.
  **소유 축을 직접 재확인**했다 — `scripts/gissue/get-issue.sh <isn> 70424` 응답 본문의 `cSn` 을 읽으니 3건 전부
  **이 세션 CSN(70424) 밖(타 CSN)**이었다(105차 KNOW-043 축).
  ⇒ 소유축 미통과 → **계승·삭제·쓰기 0건**(rule 76 · rule 46).
  (타 CSN 번호는 이 공개 저장소 기록에 쓰지 않는다 — 규칙 54.)

## [E] 열린 PR 의 CI/검증 실패 — 대상 0건

- 열린 PR 0건 ⇒ CI 실패 대상 0건.
- 원격 CI 상태 — `gh run list --repo LowyShin/giip-fde-agent --limit 8` 실측(전건 `completed`/`success`):

| run | 대상 | 결과 |
|---|---|---|
| `43382500866` | `main` push (111차 기록 PR #415 `8edeb03`) | **success** |
| `43382234416` | `main` push (slack-bot-minimax 경로 하드코딩 제거) | **success** |
| `43382206457` | PR pull_request (111차 기록) | **success** |
| `43381981107` | PR pull_request (slack-bot-minimax 경로) | **success** |
| `43371690124` | `main` push (PR #413 머지본) | **success** |
| `43370328055` | PR pull_request (PR #413) | **success** |
| `43367327995` | `main` push (Q&A 격리 이식) | **success** |
| `43366390142` | PR pull_request (Q&A 격리 이식) | **success** |

- 로컬 게이트 `scripts/gissue/run-repo-gates.ps1` — **양쪽 exit 0**(같은 base `8edeb03`):

| 실행 위치 | ps1 | mjs | 링크스캔 | 실패 | 마크다운 | 전체 링크 | 상대링크 | 스캐폴딩 | 실제 결함 |
|---|---|---|---|---|---|---|---|---|---|
| 공유 체크아웃(`8edeb03`) | 38 | 7 | 1 | **0** | 621 | 1,274 | 865 | 21 | **0** |
| 세션 워크트리(`8edeb03` + 본 회차 산출물) | 38 | 7 | 1 | **0** | 622 | 1,275 | 866 | 21 | **0** |

  (마크다운·링크 수는 추적 파일(`git ls-files`) 기준이라 신규 파일 1건과 신규 상대링크 1건은
  **스테이징 후**부터 집계된다 — 워크트리 실행은 스테이징 후 622개 = 621 + 신규 1로 일치.)

## [F] orphan auto-unblock stash — 대상 0건

- `git stash list` → **빈 목록**(등록된 stash 0건) ⇒ 적용·pop·drop 대상 0건.
- `auto-unblock` 잔여 stash 는 0건 — stash 0건이므로 대응 대상도 0건.

## 워크트리 인벤토리 · 회수

정본 정리 도구(`scripts/gissue/cleanup-worktrees.ps1`)만 사용했다 — 원시 `git worktree remove` 는 대량삭제 훅이 deny.

### 회수(세션 워크트리 1건)

- 본 회차 워크트리 `maint-112-1625` 는 **PR #416 머지 후** 정본 도구로 회수했다(실측 결과는 아래 "회수 후 재측정" 절).

### MANUAL-REVIEW 5건 — 미접촉(회수 전 측정 · 회수 후 4건)

정본 도구 DryRun 실측(`-RepoPath` 모드): 삭제 0건 · locked 제외 0건 · MANUAL-REVIEW **5건** · `Aborted=False`.

| 워크트리 | 판정 사유 | 비고 |
|---|---|---|
| `maint-112-1625` | 브랜치에 PR 없음(당시) | **이 세션 자신의 워크트리** — PR 머지 후 회수 |
| `giip-5054-refine` | 브랜치(`docs/giip-5054-task-directive`)에 PR 없음 | 스테이징된 미커밋 산출물 — 타 세션 소유분, 미접촉 |
| `maint-62-2331` | 브랜치에 PR 없음 | 미커밋 수정 2건(`docs/HISTORY.md` · `docs/WHATS_NEW.md`) — 기존 보류 유지, 미접촉 |
| `verify-4139-c7` | detached HEAD | clean — 자동 회수 경로 없음(KNOW-045) |
| `verify-5054-main` | detached HEAD | clean — 자동 회수 경로 없음(KNOW-045) |

- 고아 워크트리 스캔(`-OrphanScan -DryRun -ScanRoot "D:\temp\worktrees\giip-fde-agent"`) →
  `.git` 보유 디렉터리 6건 전부 `Registered` · **고아 0건** · `Aborted=False`.

### 회수 후 재측정(정본 도구 DryRun, 실측)

- 본 회차 워크트리 회수(2026-11-13 16:43 KST) —
  `scripts/gissue/cleanup-worktrees.ps1 -RepoPath "C:\Users\lowys\Downloads\projects\giip-fde-agent"
  -OnlyPath "D:\temp\worktrees\giip-fde-agent\maint-112-1625" -MinIdleMinutes 0`
  (DryRun 먼저 → 삭제 대상 1건 확인 → 본 실행). 판정: **머지 확인됨 · idle · locked 아님** → 삭제 1건.
- **회수 전 안전 확인** — PR head 커밋(`c3adb25`)의 두 파일 blob sha256 이 `origin/main`(`cf79cb9`)의
  같은 파일 blob sha256 과 **바이트 동일**함을 확인(2건 전건 동일) → 내용을 잃지 않음을 확인한 뒤 회수.
  심볼릭 링크·정션 0건(`find -maxdepth 3 -type l -o -type j`) · 워크트리 working tree clean.
- **회수 결과 실측** — `git worktree list` → 5줄(공유 체크아웃 + 잔여 4건) · 세션 워크트리 디렉터리 **삭제 확인** ·
  로컬 브랜치 `chore/csn70424-maint112-20261113-1625` **삭제 확인** · 원격 ref `origin/chore/csn70424-maint112-20261113-1625`
  **삭제 확인**(정본 도구가 머지 완료 분기 원격 정리를 수행).
- **회수 후 재측정** — `-RepoPath` DryRun → 삭제 0건 · locked 제외 0건 · MANUAL-REVIEW **4건**
  (`giip-5054-refine` · `maint-62-2331` · `verify-4139-c7` · `verify-5054-main`) · `Aborted=False`.
  `-OrphanScan` DryRun → `.git` 보유 디렉터리 **5건 전부 `Registered`** · **고아 0건** · `Aborted=False`.
- 공유 체크아웃은 `origin/main`(`cf79cb9`) 로 ff-sync 완료 · 미커밋 잔여는 타 세션 untracked 3건뿐(미접촉).

## [H] 최근 코멘트 논리 재검증 — 2시간 창 21건 / 24시간 창 51건

- 수집: `giipdb/mgmt/listRecentCommentIssues.ps1 -Csn 70424 -HoursBack 2 | 24 -Json`.
  **mgmt JSON 의 epoch 은 DB 값보다 9h 빠르다**(저장값이 UTC 인데 `ConvertTo-Json` 이 로컬로 간주해 재Interpretation) —
  이 보정은 KNOW-026 에 이미 정본화되어 있으므로 **실제 나이 = 계산된 나이 − 9h** 로 환산했다.
  환산 결과 **2시간 창 21건 · 24시간 창 51건**(요청 창보다 각각 +0/+0 — 실측 일치).
  본문 인코딩이 cp932 로 깨져 판독 불가 ⇒ **API 로 코멘트 본문을 직접 재조회**해 읽었다.
- 작성자 분포(마지막 코멘트 기준) — 2시간 창: watchdog 16 · 사람 3 · 없음 2 / 24시간 창: 사람 22 · watchdog 19 ·
  gissue-agent 5 · 스케줄러 1 · 감사 1 · 없음 3.
- 상태 분포 — 2시간 창: READY 10 · REVIEW 7 · PENDING 3 · DONE 1 / 24시간 창: READY 14 · REVIEW 9 · PENDING 4 ·
  DONE 23 · IN_PROGRESS 1.

### 재검증표 — 직접 실행한 것만

| 출처 | 주장 | 재검증 방법 | 결과 |
|---|---|---|---|
| watchdog `[BUDGET]` 17건(24시간 창) · `[SKIP-REASON]` 2건 | 각 이슈의 `(isn, status)` | API 현재 상태와 대조 | **전건 일치**(`STALE_IN_PROGRESS` 는 큐 파생 라벨 — 거짓 주장 아님) |
| giip 5054 | verify-runner PASS | `scripts/gissue/verify-runner.mjs 5054 70424 --json` 재실행 | **PASS**(exit 0) |
| giip 5153 · PR #413 | PR 머지 완료 · 변경 5파일 | `gh pr view 413 --json state,mergedAt,files` | **일치**(MERGED · 5파일) |
| giip 5054 · PR #407 | 머지 커밋 `41de980` | `git show` + `origin/main` 조상 확인 | **일치** |
| giip 4116 · PR #389 | 머지 커밋 `22bc20b` | `git show` | **일치** |
| 무소식 감지 도구 | `Get-LivenessEpisode` 4회 · `lib/liveness-ops-issue.js` 존재 | `git grep` + 파일 확인 | **일치**(4건 / 파일 존재) |
| `list-issues.js` | 큐 라벨 정의가 커밋됨 | `git log -- scripts/gissue/list-issues.js` → `e44e922` · 공유 체크아웃 미커밋 수정 0 | **일치** |
| giip 5141 | 상수 3건(`RECONNECT_GRACE_MS=120s` · `ACK_FAIL_LIMIT=6` · `ws_message` 에서 `markAlive` 미호출) | `origin/main` 의 `slack-bot/index.js` 실측 | **일치**(L261·L262·L350) |
| 스케줄러 가동 | 태스크 Running · 마지막 실행 16:07:07 · 락 PID 부재 | `Get-ScheduledTask` · `Get-Process` · `Get-Service` 실측 | **일치**(PID 70504 부재 · `PcaSvc` svchost 정상 가동) |
| giip 5140 | 스크립트 2종의 라인·인자 | `origin/main` 소스 실측 | **내용 일치**(줄 번호는 현재 파일 기준으로 약 6행 어긋남 — 판정 근거는 불변, 97차 선례에 따라 코멘트 없음) |
| giip 5141 | `docs/RCA_channel_allowlist_split_brain.md` 존재 | `git ls-tree` · `git grep` · `git log --diff-filter=A` 전수 탐색 | **무효** → 정정 1건 |

### 정정 1건 — giip 5141

- 직전 작업 지시서가 참조한 `docs/RCA_channel_allowlist_split_brain.md` 는 **이 저장소에 존재하지 않는다**
  (`git ls-tree -r origin/main --name-only | grep -i RCA_channel` → 0건 · `git grep split_brain origin/main` → 0건 ·
  `git log --all --diff-filter=A -- "*split_brain*"` → 0건 · 파일시스템 전수 탐색 → 없음).
  이 저장소 안의 RCA 문서는 `slack-bot/docs/RCA_result_url_missing.md` 와 `slack-bot-minimax/docs/RCA_result_url_missing.md` 뿐이다.
- 조치: `scripts/gissue/get-issue.sh 5141 70424 --comment-file <UTF-8 파일> --role .agent/roles/orchestrator.md`
  로 정정 코멘트 등록. **상태 전이는 하지 않았다** — [H] 는 READY 복귀까지만 허용하므로 READY 유지(READY -> READY, 변동 없음).
- 정정 코멘트에 함께 적어둔 후속 지시 — 이 저장소에서 해당 문서를 찾지 말고 "미확인"으로 명시할 것,
  그리고 **그 문서를 이 저장소로 복사·커밋하지 말 것**(PUBLIC 범용 저장소 · 실제 PC 이름 포함 · rule 81).
- **같은 이슈의 나머지 코드 주장(상수 3건)은 참**이어서 정정 대상에서 제외했다.

### 전이 0건

- READY 복귀·DONE·TESTED 전이 **0건**. [H] 규칙상 DONE·TESTED 전이는 금지이며, 잘못된 주장은 giip 5141 한 건뿐이라
  상태값을 건드리지 않고 정정만 남겼다.

## k-layer / tKB

- **신규 k-layer 0건 · tKB sync 대상 0건.** 이번 회차의 사실관계는 모두 기존 정규 지식(지식 정본)에 이미 있다 —

| 발견 사실 | 이미 있는 정규 지식 |
|---|---|
| mgmt JSON epoch 이 DB 값보다 9h 빠름 | **KNOW-026** (giip 이슈 regdate UTC vs JSON −9h) |
| orphan 원격 브랜치 계승 전 소유축 확인 | **KNOW-043** (105차) |
| detached HEAD 워크트리는 자동 회수 경로 없음 | **KNOW-045** (109차) |
| 정본 도구 분류가 MANUAL-REVIEW 면 우회 금지 | **KNOW-044**(fail-closed 판정) + **KNOW-045** |

  ⇒ 중복 등록 없이 **기존 노트를 인용**했다(rule 61 — 중복 등록 회피 · 번호 임의 재배정 금지).

## 규칙 54 자기검사

- 본 PR 이 추가하는 줄에서 **이 저장소 자신의 CSN(70424) 이외의 CSN 식별자**가 나왔는지 기계로 점검했다.
  - "타 CSN" 으로만 지칭했고 다른 CSN 번호는 쓰지 않았다(108·109·110·111차 기록과 동일 기준).
  - orphan 원격 브랜치 소유축 확인 결과도 **번호 대신 "이 세션 CSN 밖"** 으로만 기록했다.

## 결과 요약

- [0] 병합충돌 0건(열린 PR 0 · nested 0 · orphan 원격 ref 3건은 소유축 미통과 → 계승·삭제·쓰기 0) ·
  [E] CI 실패 대상 0건(원격 run 8건 success · 로컬 게이트 공유 체크아웃·세션 워크트리 **양쪽 exit 0**) ·
  [F] 오판 stash 0건 ·
  [H] 2시간 창 21건 / 24시간 창 51건 — **정정 1건 · 상태 전이 0건 · 이슈 쓰기 1건**.
- 별도 act **0건** · **코드 변경 0건**(문서 2건만: 본 기록 + What's New 항목).
- 워크트리 회수 **1건**(본 세션 워크트리 · PR #416 머지 후 정본 도구로 회수 — 「회수 후 재측정」 절) ·
  MANUAL-REVIEW 4건 미접촉(회수 전 5건) · 고아 0건.
- 성역(giipApi/giipApiSk2) 미접촉 · main 직접 push 없음 · PR 경유 · 명시적 경로 스테이징만.

## 남은 사항 (다음 회차가 이어받을 것)

- MANUAL-REVIEW 4건(`giip-5054-refine` · `maint-62-2331` · `verify-4139-c7` · `verify-5054-main`)은
  사람이 판단해야 회수된다 — detached HEAD 2건은 **자동 회수 경로가 없다**(KNOW-045).
- `giip-5054-refine` 의 스테이징된 미커밋 산출물은 타 세션 소유분 — 미접촉 유지.
- `maint-62-2331` 의 미커밋 수정 2건은 기존 보류분 — 미접촉 유지.
- 공유 체크아웃 untracked 3건(`.tmp-gissue-5054-*.md`)은 타 세션 소유분 — 미접촉 유지.
- orphan 원격 브랜치 3건은 소유축이 이 세션 CSN 밖 — 계승·삭제·쓰기 0건 유지.
- giip 5141 지시서의 "동일 앱 토큰 다중 인스턴스 확인" 항목은 **이 저장소 내부 범위로는 확인 불가** —
  다음 세션은 이를 블로커로 삼지 말고 "미확인"으로 명시할 것.
