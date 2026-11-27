# 매시 이슈 처리 스케줄러 표준 스펙 — 감사·판정 상세

> 본문(정본): [hourly-issue-scheduler.md](./hourly-issue-scheduler.md) 에서 분리된 절
> 모음이다 (giip #6329 — 500라인 초과 분리). 절 번호는 본문과 동일하게 유지한다.
> 담는 절: §12 안전 규칙 주입 · §13-1 감사/스윕/가드 · §13-3 되돌림 판정 · §13-3-1 증거 기반 PR 귀속 · §13-4 게이트 디바운스

## 12) 이슈 처리 세션에 반드시 주입할 안전 규칙 (giip #2465)

§5 상태머신이 "무엇을 할지"를, §11이 "그 코드가 실제로 도는지"를 다룬다면, 이 절은 **세션이
처리하는 동안 지켜야 할 안전 규칙을 어떻게 세션에게 전달하는가**를 다룹니다.

### 12-1) 배경 — 문서에만 있는 규칙은 지켜지지 않았다

2026-09-14 하루 동안 같은 계열 사고 10건이 실측으로 확인됐고, **공통점은 전부 "규칙은 문서에 있는데
매번 기억해서 지켜야 하는" 형태**였습니다. 세션 프롬프트에 주입되거나 훅으로 강제된 규칙만 실제로
지켜졌습니다(giip #2442에서 실증 — 규칙을 만든 당사자 세션이 자기가 만든 훅에 차단당했습니다).

따라서 규칙 본문의 정확성만으로는 부족하고, **전달 경로(주입)** 가 스펙의 일부입니다.

### 12-2) 정본 위치와 주입 계약

- 규칙 정본: `.agent/rules/41_issue_session_safety_index.md`(색인)와 그것이 가리키는
  `42_`~`50_` 파일들, 그리고 `.agent/rules/PROTOCOL_PROGRESS_COMMENT.md`(코멘트 시각 규정 포함).
- **프롬프트 템플릿은 이 색인 파일 1개만 가리키면 됩니다.** 규칙 본문을 프롬프트에 복제하지
  마십시오(본문 복제 금지 — §5의 상태머신 상세와 같은 원칙).
- 이 레포의 러너(`scripts/gissue/run-gissue-claude.ps1`)는 `$PromptTemplate` 안의 `{AGENT_REPO}`
  치환자로 이 색인 파일이 있는 레포 루트를 세션에 알려줍니다.

| 규칙 | 한 줄 요약 | 근거 giip |
|---|---|---|
| 42 완료 판정은 실행 결과로만 | 등록/머지는 근거가 아니다. `LastTaskResult=0`도 아니다 | #2415 #2425 #2429 #2431 #2436 |
| 43 위임 안전 블록 | worktree 격리 / install 금지+`mklink /J` / 링크 후에도 worktree 안 pnpm 의존성 변경 금지(write-through) / `--no-verify` 금지 / 자기 worktree 정리 금지 | #2390~#2397 #2432 #2442 #2476 #2487 #2497 |
| 44 `[NO-PR-REASON]` | PR이 성립 불가한 이슈의 탈출구 | #2415 #2425 |
| 45 3회 캡 이후 `NEEDS_DECISION` | 4분기 재판정, 예·아니오 질문 1개 | #2415 #2425 |
| 46 타 CSN 쓰기 금지 | 읽기는 되고 쓰기는 안 된다 | #1053 #1079 |
| 47 자동 정리 안전 요건 | idle 가드 / locked 스킵 / 링크 게이트 / 항목별 검증 / 로그 | #2432 #2445 #2463 #1540 |
| 48 안전 판정 공용 함수 1개 | 복붙 중복 금지(코드와 프롬프트 문단 양쪽) | #2440 #2463 #2425 |
| 49 문구 매칭 오탐 방지 | 주어·시제 구분. 애매하면 잡지 않는다 | #2424 #2457 |
| 50 봇 PR 범위 규율 | `git add -A` 금지, 머지 전 `--json files` 확인 | #2424 #2459 |

### 12-3) ⚠️ 주입 블록은 프롬프트에 **단 한 번만** 둔다

원본 구현(`lowyworkenv/scripts/gissue/run-gissue-claude.ps1`)의 프롬프트 템플릿에는 **같은 안전
문단이 2벌 존재**했습니다 — `[C]` READY 처리용 1벌, `[D]` stale IN_PROGRESS 회수용 1벌. 한쪽만
고쳐진 결과, 어느 단계를 타느냐에 따라 규칙이 적용되기도 하고 안 되기도 했습니다(giip #2425 실측).

**따라서 이식할 때는 주입 블록을 `[0]`~`[H]` 각 단계가 아니라 템플릿 최상단(모든 단계 공통 영역)에
한 번만 넣습니다.** 각 단계는 "위 [안전 규칙 로드] 그대로 따른다"로 참조만 합니다.

> 이미 2벌 이상이 존재하는 이식본을 고칠 때는 **양쪽을 모두 검색해 함께 고치거나 한 벌로
> 합칩니다.** 한쪽만 고친 PR은 "고쳤다"고 보고되지만 실제로는 절반만 동작합니다.
> 자기 이식본에 블록이 몇 벌인지 먼저 세어 보십시오(블록 헤더가 줄 맨 앞에 오는 것만 셉니다 —
> 본문 안의 `"위 [안전 규칙 로드] 그대로 따른다"` 같은 참조는 세지 않습니다):
>
> ```powershell
> (Select-String -Path .\scripts\gissue\run-gissue-claude.ps1 -Pattern '^\[안전 규칙 로드\]').Count
> ```
>
> 기대값은 **1**입니다. 2 이상이면 §12-3 위반이므로 한 벌로 합친 뒤 진행하십시오.

### 12-4) 주입이 실제로 됐는지 확인하는 방법

프롬프트에 문구를 넣은 것만으로는 확인이 아닙니다(규칙 42). 아래까지 해야 "주입됐다"입니다.

1. `-DryRun -OnlyCsn <csn>`으로 실행해, 생성된 프롬프트에서 `{AGENT_REPO}`가 **실제 경로로
   치환됐는지** 확인한다(치환자가 그대로 남아 있으면 실패).
2. 그 경로에 `.agent/rules/41_issue_session_safety_index.md`가 **실제로 존재하는지** 확인한다
   (러너만 복사하고 규칙 파일을 빠뜨린 이식은 여기서 걸린다).
3. 한 사이클을 실제로 돌린 뒤, 세션이 남긴 착수 코멘트의 로드 목록에 그 규칙 파일이 적혀 있는지
   확인한다(`.agent/rules/PROTOCOL_PROGRESS_COMMENT.md` §"남기는 시점 1) 착수" 규정).

## 13-1) 감사·스윕·가드 스크립트와 공용 lib (giip #2645)

`:07` 본체(`run-gissue-claude.ps1`)가 부르는 **무결성 가드 / PR 감사 / 스윕** 계열이 이 레포에
들어와 있습니다. 아래는 그 목록과, 원본(`lowyworkenv`)과 **동작이 다른 지점**입니다 — 다른
지점만 적습니다. 나머지는 원본과 동일하게 동작합니다.

### 13-1-1) 무결성·안전 가드

| 파일 | 역할 |
| :-- | :-- |
| `scripts/gissue/verify-nested-repo.ps1` | nested 체크아웃 무결성 6종 검사(경로 존재 / 유효 git 레포 / **bare 아님** / origin 접미사 일치 / `-RequiredFiles` 존재 / `-RequiredPsDir` 안 `*.ps1` 1개 이상). 마지막 줄은 항상 `RESULT: PASS` 또는 `RESULT: FAIL: <사유>…`, exit 0/1 |
| `scripts/gissue/worktree-safety.ps1` | worktree 판정·삭제 엔진 정본(rule 55 절차 내장) |
| `scripts/gissue/cleanup-worktrees.ps1` | 위 엔진의 CLI 진입점(`-RepoPath` / `-AllRepos` / `-OrphanScan` / `-RemnantScan`) |
| `scripts/gissue/code-freshness.ps1` | "지금 메모리의 코드가 낡았는가" 가드. 낡았으면 파괴적 작업을 건너뛰고 다음 `:07` 에 넘긴다 |

`verify-nested-repo.ps1` 은 **의도적으로 detect-and-halt 전용**입니다. 자동 재clone / 자동 복구를
추가하지 마세요 — 애초에 "무언가 잘못된 레포를 자동으로 clone 했다"가 giip #1365 사고의 원인이고
그 프로세스는 아직 특정되지 않았습니다. 복구는 사람이 판단합니다.

`cleanup-worktrees.ps1` 의 orphan 정리는 **(a) git worktree 로 정식 등록되지 않았고 (b) 이슈가
DONE 이거나 이슈 자체가 없고 (c) 24시간 이상 방치된** 것만 지웁니다. READY/PENDING/IN_PROGRESS/
REVIEW/TESTED 이슈에 연결된 워크트리와 `git worktree list` 에 정식 등록된 워크트리는 **절대**
건드리지 않습니다(사람이 그 안에서 작업 중일 수 있습니다). 배경은 §10 과 giip #1540 입니다.

> **정정(2026-11-14, isn=5175)** — 위 문장은 **orphan 정리(`-OrphanScan`) 경로**에 대한 것입니다.
> `git worktree list` 에 **정식 등록된** 워크트리는 별도 경로(`-RepoPath` / `-AllRepos`)에서
> "머지 확인 → 미커밋 변경 확인 → 링크 선검사 → idle 가드" 를 태워 **삭제될 수 있습니다**
> (사람이 작업 중이거나 미반영 커밋이 있으면 protected / MANUAL-REVIEW 로 남습니다).
>
> 또한 Claude Code 격리 계열(`.claude/worktrees/agent-*`) 은 이전까지 **무조건 제외**됐으나,
> 그 결과 어떤 자동 정리 경로에도 잡히지 않아 레포당 수십 개가 무한 누적됐습니다
> (2026-11-13 실측: 27건 + `D:\temp\worktrees` 60여 건). 이제 이 계열도 **같은 안전 요건을
> 태운 뒤에야** 정리 대상이 되며, 이 계열에만 3가지가 추가됩니다.
>
> 1. **"고유 커밋 없음" 판정 병행** — 이 계열의 브랜치(`worktree-agent-<id>`)에는 PR 이 없는
>    로컬 전용 브랜치가 많아 PR 머지 게이트만으로는 정리 대상이 0건이 됩니다. 그래서
>    "worktree 의 HEAD 커밋이 `origin/main` 의 조상인가"(= 고유 커밋이 이미 main 에 반영됨 →
>    내용 유실 없음)를 판정해 병행합니다. 판정 불가·미반영은 모두 **삭제 금지(fail-closed)** 이며,
>    squash 머지 브랜치는 조상이 아니므로 PR 게이트와 서로를 보완합니다.
> 2. **격리 메커니즘 산출물의 dirty 제외** — Claude Code 는 worktree 마다 세션 권한을
>    `.claude/settings.local.json` 에 기록하므로, 산출물로 취급하면 이 계열이 영영 정리 대상 0건이
>    됩니다. **이 파일만** dirty 판정에서 제외하고(제외 사실은 로그에 남깁니다), 그 밖의 미커밋
>    변경은 어떤 경우에도 자동 삭제 금지입니다. 미추적 디렉터리는 `git status -uall` 로 개별
>    파일로 펼쳐야 경로 매칭이 통합니다.
> 3. **idle 하한 240분** — 라이브 서브에이전트가 오래 붙잡고 있는 경우를 보호합니다
>    (idle 가드가 실행 중 에이전트 보호를 겸함).
>
> 정리 도구가 **못** 지우는 것(타 세션 소유 · 미커밋 산출물 · 진행 중)은 위임자(오케스트레이터)가
> 직접 판단해 정리하거나 보고합니다 → [오케스트레이터 역할](../../.agent/roles/orchestrator.md).
> 근거 규칙: [규칙 47](../../.agent/rules/47_auto_cleanup_safety_requirements.md) ·
> 회귀 테스트: `scripts/gissue/tests/test-worktree-claude-session-guard.ps1`.

> **확장(2026-11-27, giip 6401/6423)** — 위 "고유 커밋 없음"(조상) 판정은 **격리 계열 전용이 아니다**.
> **모든 worktree** 에 병행한다. 추가한 이유: `gh pr list --state merged --json headRefName` 는
> **PR 헤드 브랜치 이름**만 준다. PR 이 없는 로컬 전용 검증 브랜치이거나 PR 헤드 이름과 worktree 의
> **로컬 브랜치 이름**이 다르면 그 worktree 는 PR 머지 게이트만으로는 **영영** '미머지' 로 남아
> **정리 대상이 0건**이 된다 — 무한 누적의 잔류 경로다. 실측(giip 6401, 2026-11-26): 이 레포 잔여
> worktree 5건 **전부** HEAD 가 `origin/main` 의 조상인데도 5건 전부 MANUAL-REVIEW 였다.
>
> **★ 하한선(필수)** — 조상 판정은 **커밋된 내용**만 증명한다("HEAD 가 조상" = 커밋된 내용은 이미
> `main` 에 있음). **미커밋 산출물은 그 증명에 포함되지 않는다.** 그래서 이 경로는 dirty 판정을
> **엄격하게** 태운다 — 미커밋 변경 1건이라도 있으면 **삭제하지 않고 보류**(MANUAL-REVIEW)한다
> (규칙 57 의 "❌ 미커밋 변경이 있는 worktree 삭제" 가 그대로 적용된다).
> PR 머지 게이트를 통과한 경로의 기존 동작(더티여도 진행)은 **그대로 둔다** — 변경 범위는 "조상 판정 경로" 다.
> 근거 규칙: [규칙 47](../../.agent/rules/47_auto_cleanup_safety_requirements.md) ·
> 회귀 테스트: `scripts/gissue/tests/test-worktree-ancestry-general-guard.ps1`
> (조상+clean → 정리 대상 / 조상+미커밋 → 보류 / 조상+미반영 → 보류 / PR 게이트 경로 기존 동작 유지).

**실행 셸**: 이 레포의 배포 대상에는 PowerShell 7(`pwsh`)이 없을 수 있습니다. 문서 예시와 실제
호출은 전부 `powershell -NoProfile -ExecutionPolicy Bypass -File "<경로>"`(Windows PowerShell 5.1)
로 씁니다 — `pwsh` 로 부르면 `command not found` 로 **아무 일도 하지 않고** 끝납니다(giip #2559).

**인코딩**: 이 레포의 `.ps1` 은 전부 **UTF-8 with BOM** 으로 저장합니다. PowerShell 5.1 은 BOM 이
없는 파일을 시스템 ANSI 코드페이지로 읽습니다 — BOM 없는 `.ps1` 6개가 파서 검사를 "6개 전부 통과"
받고도 `powershell -File` 실행에서는 파서 에러 7건으로 한 줄도 실행되지 않은 실측이 있습니다
(giip #2590/#2591). BOM 3바이트를 붙이자 정상이 됐습니다.

### 13-1-2) PR 감사·스윕

| 파일 | 역할 |
| :-- | :-- |
| `scripts/gissue/review-done-audit.ps1` | REVIEW/DONE 완료위조 감사 + 상태전이 + 후속 이슈 생성 |
| `scripts/gissue/pr-attribution-lib.ps1` / `pr-attribution-sweep.ps1` | 머지 PR 의 타-이슈 파일 혼입 귀속 판정·코멘트 |
| `scripts/gissue/gissue-gate-tally-lib.ps1` | 게이트 되돌림 **전체 합산** 집계(에스컬레이션 판단용) |
| `scripts/gissue/audit-review-prs.mjs` | REVIEW 이슈의 PR 존재 여부 감사(Node) |
| `scripts/gissue/verify-runner.mjs` | 이슈 본문 ` ```verify ` 블록 실행기(exit 0=PASS/1=FAIL/2=블록없음/3=조회실패) |
| `scripts/gissue/lib/pr-lookup.mjs`, `lib/pr-lookup-cli.mjs`, `lib/audit-repos.mjs` | PR 탐지/감사대상 레포 탐색 공용 lib |
| `scripts/gissue/lib/check-comment-timestamp.js`, `lib/resolve-actor.js` | 코멘트 시각 검증, AI 행위자 자격증명 해석 |
| `scripts/gissue/register-issue.js` | 후속 이슈 등록 |

### 13-1-3) ⚠️ 원본과 다른 점 — 쓰기 경로가 API 하나뿐이라 생긴 차이

이 레포에는 DB 직접접속 수단이 없습니다(§4 "혼용 이식은 금지"). 그래서 원본이
`giipdb/mgmt/addIssueComment.ps1` / `updateIssueStatus.ps1` 로 하던 쓰기를 전부 API 로 바꿨습니다:

- 코멘트 등록 → `scripts/gissue/lib/post-comment.js`(등록 → 즉시 재조회 → mojibake 검증 → 1회 재시도).
  본문은 반드시 UTF-8 파일로 넘깁니다(giip #1030).
- 상태 전이 → `PUT <ApiBaseUrl>/giipIssues` (status-only. 제목/본문은 SP 가 ISNULL 로 보존).
- 따라서 `-MgmtDir` 파라미터는 `review-done-audit.ps1` / `pr-attribution-sweep.ps1` 에 **없습니다**.

**그 결과 되돌림/감사 코멘트 판정이 author 기반에서 마커 기반으로 바뀌었습니다.** API 경로에서는
author 를 클라이언트가 지정할 수 없고 서버(`pApiGiipIssueComment*byAK`)가 인증 주체의
`tCorpUser.uname` 으로 강제합니다. `author -eq 'gissue-review-audit'` 같은 AND 조건을 그대로 두면
이 레포에서는 **자기 과거 코멘트를 한 건도 못 찾아** 멱등성·loop guard·3회 캡·전체 합산
에스컬레이션이 통째로 무력화되고 같은 이슈에 코멘트가 무한히 쌓입니다. 그래서 다음 판정은 전부
마커 문자열만 봅니다(`pr-gate-sweep.ps1` 은 원래부터 그랬습니다):

- `gissue-audit-lib.ps1`: `Test-AlreadyRevertedByMarker`, `Get-GateRevertAttemptCount`,
  `Get-GateRevertHistorySummary`
- `gissue-gate-tally-lib.ps1`: `Get-GateRevertTally`
- `review-done-audit.ps1`: `Test-IsAuditComment`(author 일치 **또는** `[REVIEW-AUDIT:` 마커 포함)

마커는 게이트마다 고유하고, `gissue-gate-tally-lib.ps1` 상단의 "카운팅 오염 방지" 규약이
"이 파일이 만들어 내는 어떤 문자열에도 마커 원문을 넣지 않는다"를 보장하므로 마커 단독으로
충분히 변별됩니다. **이 규약을 깨고 에스컬레이션 본문에 마커 원문을 넣으면 그 코멘트 자신이
다음 회차 카운트를 부풀립니다.**

### 13-1-4) 저장소 후보 수집 판정 — 커밋 0건 제외 + EAP 비파괴 probe (giip 5102)

러너·스윕 계열이 "담당 프로젝트 + 직계 nested git 레포" 를 후보로 모을 때, `.git` 존재만으로
후보를 받으면 **`git init` 만 된 커밋 0건 잔여 스캐폴드**가 저장소로 오인됩니다. 그러면 두 증상이 납니다.

1. **busy-wait/auto-unblock 이 예외로 죽음** — 커밋 0건(unborn HEAD) 디렉터리에서 `git rev-parse` 가
   실패하는데, Windows PowerShell 5.1 + `$ErrorActionPreference='Stop'` 환경에서는 네이티브 git 의
   stderr 가 `2>$null` 이어도 `NativeCommandError` 로 **throw** 됩니다.
2. **스윕 3종 전멸** — `pr-gate-sweep.ps1` / `review-done-audit.ps1` / `pr-attribution-sweep.ps1` 은 모두
   EAP=Stop 이라, `Get-NestedRepoPaths`(`gissue-audit-lib.ps1`) 의 `remote get-url origin` probe 가
   같은 이유로 throw 되어 **저장소 수집 단계에서** 스윕 전체가 죽습니다(관측: `No such remote 'origin'`).
   의도된 "origin 없는 디렉터리 제외" 로직이 한 번도 실행되지 않습니다.

판정 규칙(현행 구현):

- `Get-GissueGitRepoPaths`(러너 메인/잡 스코프 + `run-slackbot-restart-check.ps1` 사본)는 **후보 루프 안에서**
  `git rev-parse --verify HEAD` 를 EAP=Continue + `$LASTEXITCODE` 로 판정해, 실패(커밋 0건)면 그 디렉터리를
  `[WARN][EMPTY-REPO-SKIP]` 로그와 함께 제외합니다. **자기 저장소(`$workdir`)는 루프 바깥에서 먼저 추가**되므로
  이 판정 대상이 아니며 커밋 0건이어도 항상 유지됩니다(빠지면 러너 전체가 무력화됩니다).
- `Get-NestedRepoPaths` 의 origin probe 도 EAP=Continue + 종료코드로 판정해 예외 없이 돌리고, origin 이
  없는 디렉터리만 제외합니다(로컬 전용 저장소를 잘못 버리지 않기 위해 **origin 부재는 커밋 0건 판정과 별개**).
- `Get-GissueBusyRepo`(러너 메인 스코프 + 잡 스코프 사본)의 **브랜치 probe** 도 같은 형태로 비파괴화돼
  있습니다 — `git rev-parse --abbrev-ref HEAD` 를 EAP=Continue + `$LASTEXITCODE` 로 판정해, unborn HEAD
  나 깨진 `.git` 처럼 probe 가 실패한 저장소는 busy 판정 대상에서 건너뛰고 **예외를 던지지 않습니다**.
  이 판정이 없으면 busy-wait/auto-unblock 이 저장소 후보 수집이 끝난 **그 다음 단계에서** 러너/잡
  전체를 죽입니다(giip 5180).
- 회귀 테스트: `scripts/gissue/tests/test-git-repo-paths.ps1` — AST 로 배포본 함수 본문을 그대로 추출해
  모든 사본을 검증하고, neg 컨트롤로 판정의 변별력(빈 통과 배제)을 확인합니다. D 그룹은
  `Get-GissueBusyRepo` 사본 전부에 대해 ① EAP=Stop 에서 예외 미발생 ② 반환 계약(Repo/Branch/Base
  객체 또는 null) ③ 비-base 브랜치 저장소의 busy 판정이 여전히 동작 ④ 모든 사본의 EAP 비파괴 패턴
  존재를 확인하고, neg 컨트롤로 비파괴화 전 형태가 실제로 throw 함을 확인합니다.

### 13-1-5) 시크릿 파일 위치 — `GIIP_ACCOUNTS_FILE`

`slack-bot/.secrets/giip-accounts.json` 은 git 비추적이라 **워크트리 체크아웃에는 없습니다**.
원본은 이 PC 절대경로를 폴백으로 박아 뒀지만 이 레포는 그럴 수 없으므로, 환경변수
`GIIP_ACCOUNTS_FILE` 로 그 파일 경로를 지정할 수 있게 했습니다(지정하면 그쪽이 우선).
`lib/resolve-actor.js` 와 `audit-review-prs.mjs` 가 같은 규칙을 씁니다.

```bash
GIIP_ACCOUNTS_FILE=/path/to/giip-accounts.json node scripts/gissue/lib/resolve-actor.js --json
```

AK 자체는 이 레포에서 발급/조회할 수 없습니다(DB 전용). 절차는
`scripts/gissue/AI_ACTOR_ACCOUNTS.md` §0-1 의 절별 가부 표를 보세요.

### 13-1-6) PR 탐지 범위 — `audit-extra-repos.json` (giip #2504)

어느 프로젝트 폴더 아래에도 clone 되지 않은 레포(예: `LowyShin/giipAgentLinux`)의 PR 은 워크디렉터리
스캔으로는 절대 안 잡혀, PR-gate 가 "PR 없음"으로 REVIEW 를 되돌립니다. `audit-extra-repos.json`
의 `slugs` 에 `OWNER/REPO` 를 적으면 로컬 clone 없이 `gh pr list --repo <slug>` 로 직접 조회합니다.

**PowerShell(`Get-ExtraAuditRepoSlugs` in `gissue-audit-lib.ps1`)과 Node(`loadExtraRepoSlugs` in
`lib/audit-repos.mjs`)가 반드시 같은 파일을 읽습니다 — 한쪽만 넓히면 같은 오탐이 계속 납니다**
(giip #2464 의 교훈). 이 단일 출처 구조를 깨지 마세요.

### 13-1-7) 감사 대상 workdir 지정 — `audit-review-prs.mjs --workdir`

원본은 감사 대상 컨테이너 이름을 `giipprj` 로 하드코딩했습니다. 이 레포는 다음 우선순위로 찾습니다:

1. `--workdir <경로>` (명시 지정)
2. `csn-projects.json` 의 `csn[<--csn>].workdir`
3. `<projects>/giipprj` (기존 배포 호환)

```bash
GIIP_ACCOUNTS_FILE=<...> node scripts/gissue/audit-review-prs.mjs --csn <csn> --json
```

### 13-1-8) 회귀 테스트 — 이식/수정 후 반드시 돌린다

```powershell
# 먼저 레포 전체 .ps1 의 구문 + BOM 일괄 검사
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\check-ps1-parse.ps1 -All

# PowerShell 테스트 9종
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\tests\test-repo-integrity-gate.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\tests\test-worktree-idle-guard.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\tests\test-stale-code-guard.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\tests\test-scope-gate-pr-identification.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\tests\test-pr-attribution-noop.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\tests\test-humanconfirm-signal.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\tests\test-task-cadence-guard.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\tests\test-verify-runner-korean-encoding.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\tests\test-verify-gate-exit-contract.ps1
```

```bash
# Node 테스트
node scripts/gissue/tests/test-pr-lookup.mjs
```

**전부 인자 없이 실행해 exit 0 이어야 합니다.** 각 테스트는 마지막 줄에 `결과: PASS=N FAIL=0`
형태의 집계를 냅니다. 호스트 환경에 따라 일부 케이스는 `SKIP` 으로 표시될 수 있습니다
(예: `giipprj` 컨테이너 배치가 없는 PC) — SKIP 은 실패가 아니며 exit 0 을 유지합니다.

**`test-verify-gate-exit-contract.ps1` 은 대상 CSN 을 스스로 정합니다**(giip #2645). 라이브 케이스
A-3b 는 `-LiveCsn` 기본값(`0`)일 때 `csn-projects.json` 의 **첫 번째 enabled CSN** 을 읽습니다.
설정 파일이 아직 없는 clone 직후에는 그 케이스를 건너뛰되 **사유를 반드시 출력**합니다.

| 상태 | 결과 (실측, 2026-09-17) |
|---|---|
| 설정 없는 clone 직후 | `SKIP A-3 … csn-projects.json 이 없습니다` → `PASS=22 FAIL=0`, exit 0 |
| `csn-projects.json` 채운 뒤 | 첫 enabled CSN 자동 선택 → `PASS=24 FAIL=0`, exit 0 |
| 특정 CSN 을 강제 | `-LiveCsn <CSN>` |
| 라이브 조회 자체를 생략 | `-SkipLive` → `PASS=22 FAIL=0` |

> 이전 판(PR #86 시점)은 기본값이 **33**(원본 PC 의 CSN)이라 다른 배포에서는 clone 직후부터
> `PASS=23 FAIL=1` 로 반드시 실패했습니다. 이식된 레포의 테스트가 clone 직후 실패하면 사람이
> "원래 실패하는 테스트"로 학습해 **진짜 실패를 놓치므로**, 기본값 자체를 고쳤습니다.
> A-3b 의 판정도 하위 도구의 메시지 문자열(`조회 실패`) 매칭에서 **종료코드 판정**으로 바꿨습니다
> (`verify-runner.mjs` 의 계약: 0=PASS / 1=FAIL / 2=verify 블록 없음 / 3=판정 불가).

## 13-3) REVIEW/DONE 되돌림 판정 = 의뢰 체크리스트 (giip 4334)

사후 점검(`pr-gate-sweep.ps1`, `review-done-audit.ps1`)이 REVIEW/DONE 이슈를 READY 로 되돌리는 근거를
"대응 PR 이 있고 머지됐는가"에서 **"의뢰 항목이 전부 이행됐는가"** 로 바꾸는 사양입니다. 의뢰는 보통 복수
항목이고 문서 등록·외부 설정·조사처럼 코드 변경이 아닌 항목이 섞여 있는데, PR 유무 하나로 전체 완료를 뒤집으면
정상 완료가 반복해서 되돌려집니다(분류 자체도 키워드 근사치였습니다).

### 판정 규칙

| 단계 | 내용 |
|---|---|
| 1. 분해 | 이슈 본문 + 의뢰를 확정/재정의한 코멘트를 서로 독립적으로 확인 가능한 항목으로 나눕니다(경량 LLM, 도구 없음 — `Invoke-ChecklistJudge`). 각 항목은 `code`(소스 변경 필요) / `other`(문서·설정·조사·운영 조치). |
| 2. 항목 판정 | 항목마다 `MET`(충족) / `UNMET`(미충족) / `UNDETERMINED`(판정불가) + 근거(코멘트·PR·증적 링크). PR 머지는 **`code` 항목의 증거 중 하나**일 뿐입니다. `code` 항목이 `MET` 인데 머지된 PR·커밋 링크 증거가 없으면 자동 보정합니다(미머지 PR 이 있으면 `UNMET`, PR 자체가 없으면 `UNDETERMINED`). |
| 3. 결정 | 전 항목 `MET` → **KEEP**(현 상태 유지/확정). `UNMET` 1건 이상 → **REVERT**(READY). `UNMET` 0건 + `UNDETERMINED` 있음 → **HOLD**(되돌리지 않고 NEEDS_DECISION + 필요한 증거 명시). 판정 호출 실패·빈 응답·항목 파싱 실패 → **전이 없음**. |
| 4. 코멘트 의무 | 모든 전이는 `## 의뢰 체크리스트 판정` 절(전 항목)을 담은 감사 코멘트와 함께여야 합니다. 마커: `[REVIEW-AUDIT:CHECKLIST-REVERT]` / `-HOLD` / `-KEEP`. Live 모드의 `review-done-audit` 은 이 코멘트가 등록되지 않은 isn 의 READY/DONE 전이를 코드로 차단합니다(`[CHECKLIST-GUARD]`). |
| 5. 후속 세션 | REVERT 코멘트의 `## 미충족 항목 (다음 세션 작업 범위)` 절(`- [ ] (C<번호>) ...`)이 다음 세션의 우선 작업 범위입니다. `run-gissue-claude.ps1` 의 [C] 지시문이 이를 강제하고, `Get-LatestUnmetChecklistItems` 가 같은 형식을 파싱합니다. |
| 6. 흡수된 게이트 | PR 없음 단독 REVERT / scope-gate / comment-gate / 보고형(`[NO-PR-REASON]`) 대조 / VERIFY-GATE 실패는 별도 되돌림이 아니라 항목 판정의 **증거**입니다(VERIFY-GATE 실패는 "verify 블록 PASS" 미충족 항목으로 합류). |
| 7. 무한루프 방지 | 전 게이트 합산 되돌림 횟수(`Get-GateRevertTally`, 신규 키 `checklist` 포함)가 캡(기본 3)을 넘거나, 직전 REVERT 와 미충족 항목 집합이 같으면 더 되돌리지 않고 WARN(`review-done-audit`) / NEEDS_DECISION(`pr-gate-sweep`) 으로 에스컬레이션합니다. 기존 "동일 코멘트 반복 → WARN" 도 `CHECKLIST-REVERT` 에 적용됩니다. |

적용 범위: `review-done-audit` 에서는 구룰이 **PR-전용 REVERT** 를 내거나(Modification 분기) **DONE 승격(PASS)** 을 내는 지점에만 개입합니다. 구룰이 되돌리지 않던 경로(FINAL 유지, `[NO-PR-REASON]` 유지, Uncertain 스킵)에서 새 되돌림을 만들지는 않습니다.

### 판정 호출 방식 — stderr 분리 · 자식 종료코드 판정 · 유한 대기

판정 LLM 호출(`Invoke-GissueJudge` → claude CLI)은 **네이티브 CLI 를 부르는 한 지점**이며, 호출 방식이
판정 결과 자체를 결정한다. 아래 3가지를 지켜야 한다.

| 항목 | 규칙 | 근거 |
|---|---|---|
| **stdout/stderr 분리** | 자식 stderr 를 stdout 에 합치지 않는다(`2>&1` 금지). 성공/실패는 stderr 유무가 아니라 **자식의 실제 종료코드**로 판정한다. stderr 는 **진단 사유 전용**(판정 본문 아님)이고 300자로 자르며 `sk-…`·`x-functions-key`·`API_KEY`·`Bearer` 는 마스킹한다. | Windows PowerShell 5.1 은 네이티브 exe 가 stderr 에 **한 줄이라도** 쓰면 그것을 `NativeCommandError`(ErrorRecord)로 감싸 **종료성** 오류로 만든다. 호출자(`pr-gate-sweep.ps1`·`review-done-audit.ps1`)의 `$ErrorActionPreference='Stop'` 아래에서 함수의 catch 가 `exit=-1` 을 돌려주면 `ok=$false` → `Decision='HOLD'` 가 된다. claude CLI 는 `ANTHROPIC_API_KEY` 가 설정된 환경에서 "connectors are disabled" 경고를 stderr 에 항상 찍으므로 **gair 경유 판정은 매 회차** 이 상태에 걸린다. |
| **유한 대기** | 판정 호출에는 시간 한도가 있다 — `GISSUE_CLAUDE_CALL_TIMEOUT_SEC`(기본 **300초**, `Resolve-GissueBoundedCallTimeoutSec -Kind 'Claude'`). 한도 초과 시 자식을 종료시키고 **실패**로 표면화한다(`timedout=1`). 타임아웃을 성공으로 취급하지 않는다. | 종전엔 타임아웃이 없어 판정 호출이 **무한 대기**했다(실측 9분+ 무응답). 스윕 전체가 그 동안 붙잡혀 있었다. |
| **gair → 직접 폴백 1회** | gair 경로가 응답을 주었는데 `ITEM\|` 줄이 0건이면 **직접 경로로 1회** 재호출한다. 이때 `ANTHROPIC_BASE_URL`·`ANTHROPIC_API_KEY`·`ANTHROPIC_CUSTOM_HEADERS` 를 비운다(그대로 두면 같은 응답 형식이 그대로 나온다). 폴백까지 0건이면 기존 **HOLD 유지** — 실패를 성공으로 뒤집지 않는다. | gair 라우터는 `--model` 을 honor 하지 않아 응답이 에이전트 마크업일 수 있다 → `ITEM\|` 파싱 0건 → HOLD. 직접 경로는 정상 `ITEM\|` 줄을 준다. |

**실패 사유**에는 실제 종료코드 · 경로(`gair` / `direct` / `gair-fallback-direct`) · stderr 요약이 반드시 들어간다
(종전 사유는 `exit=<n>` 뿐이라 과거 `exit=1` 사례가 설명되지 못했다). 사유는 감사 코멘트와 로그에 남으므로
사람이 로그만 보고 원인을 확인할 수 있어야 한다.

판정 실패는 언제나 **전이 없음**(REVIEW 유지)이라는 계약은 그대로다. 회귀 테스트는
`scripts/gissue/tests/test-checklist-judge-stderr.ps1`(가짜 CLI 스텁 · LLM/네트워크 미사용).

### 모드와 롤아웃 (Live 는 명시적으로만)

`-ChecklistMode Off|Shadow|Live` (미지정이면 환경변수 `GISSUE_CHECKLIST_MODE`, 그것도 없으면 **Shadow**). `-Live`(쓰기 허용)와는 별개의 스위치입니다.

| 모드 | 동작 |
|---|---|
| `Off` | 신규 로직 없음(종전 동작). |
| `Shadow`(기본) | 구룰이 그대로 동작합니다. 구룰이 되돌리려는 이슈마다 신룰 판정을 계산해 `scripts/gissue/logs/checklist-shadow.jsonl` 에 한 줄(구룰 결론·신룰 결론·항목별 판정)로 **기록만** 합니다. 코멘트·상태 쓰기 없음. |
| `Live` | 신룰이 PR-전용 되돌림을 대체합니다. 아래 롤아웃 조건을 만족한 뒤에만 켭니다. |

롤아웃 절차(이슈 4334 변경 지시 8):

1. `compare-checklist-vs-legacy.ps1` 로 최근 2주 실제 되돌림 표본에 신·구 판정을 병행합니다(읽기 전용). 핵심 지표는 `newKeep_legacyMisjudgeEstimate`(구룰 되돌림 중 신룰로는 유지되는 건수 = 오판 추정). 결과를 이슈 코멘트로 보고합니다.
2. Live 전환 후 `-LiveSince <전환 시각>` 으로 같은 스크립트를 돌려 **"체크리스트 없는 되돌림 전이"가 0건** 인지 확인합니다. 0건이 아니면 `GISSUE_CHECKLIST_MODE` 를 Shadow 로 되돌립니다.

```powershell
# 신·구 병행 비교(읽기 전용; 표본 판정에 claude -p 호출 — 표본당 1~2분)
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\compare-checklist-vs-legacy.ps1 -Csn <csn> -Workdir "<프로젝트 workdir>" -Days 14 -MaxSamples 30 -OutFile "<결과.json>"
# Live 전환 후 검증
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\compare-checklist-vs-legacy.ps1 -Csn <csn> -Workdir "<프로젝트 workdir>" -Days 7 -LiveSince 2026-11-01T00:00:00Z
# 판정 케이스 테스트
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\tests\test-checklist-judgement.ps1
```

해석 시 주의: 비교 스크립트의 PR 증거는 되돌림 당시가 아니라 **조회 시점** 상태입니다(코멘트는 되돌림 직전까지로 잘라 판정). 표본 수가 적은 CSN 에서는 통계적 의미가 약합니다.

### 저장 위치 / 소비처

| 산출물 | 위치 | 소비처 |
|---|---|---|
| 체크리스트 감사 코멘트 | giip 이슈 코멘트 (`[REVIEW-AUDIT:CHECKLIST-*]`) | 다음 스케줄러 세션([C] 지시문), 사람, `Get-GateRevertTally`(REVERT 만 집계) |
| Shadow 기록 | `scripts/gissue/logs/checklist-shadow.jsonl`(gitignore; 실패는 `checklist-shadow-failures.jsonl`) | 롤아웃 판단(사람), 비교 스크립트 보조 |
| 비교 결과 | `-OutFile` 로 지정한 JSON | 이슈 코멘트 보고(사람) |

### Shadow 비용 축소 (giip 4334 후속)

Shadow 는 구룰이 되돌리려는 이슈마다 판정 LLM(haiku)을 1회 부른다. 같은 이슈가 같은 이유로 틱마다 다시 평가되면 호출이 낭비되므로 **Shadow 경로에만** 아래를 적용한다(`gissue-audit-lib.ps1` 의 `Test-ChecklistShadowSkip` / `Invoke-ChecklistShadowJudge`). `Live`/`Off` 는 이 구역을 쓰지 않으며, Live 판정(`Invoke-ChecklistAssessment`)은 캐시 없이 매번 새로 계산한다.

| 단계 | 동작 | 기본값 |
|---|---|---|
| (b) 평가 대상 축소 | 같은 `(isn, source)` 의 Shadow 기록이 최근 TTL 시간 안에 있으면 입력 조회(API/gh)와 LLM 호출을 모두 생략한다. `source` 는 구룰 사유(`pr-gate-sweep:PR-gate`/`scope-gate`/`comment-gate`/`report-gate`, `review-done-audit:DONE`/`REVIEW`)다. | TTL 24시간 |
| (b) 호출 상한 | 프로세스(스크립트 1회 실행 = 1틱) 당 실제 LLM 호출 수 상한 + 최근 1시간 전 프로세스 합산 상한(두 스크립트·여러 CSN 이 같은 로그를 공유하므로 로그 기준으로 센다). 캐시 적중은 세지 않는다. | 틱당 5, 시간당 20 |
| (a) 입력해시 캐시 | 판정기가 보는 입력 전부(의뢰 본문 + 코멘트 이력 전체 + PR 증거 + 판정 모델 + 프롬프트 버전)의 SHA-256(`inputHash`)이 같은 직전 기록이 있으면 LLM 을 부르지 않고 그 판정을 재사용한다(`cached=true`, `reusedFromTs` 기록). 입력이 한 글자라도 바뀌면 해시가 달라져 재호출하므로 판정 정확성에 영향이 없다. 부분 해시(`contentHash`, `scopeCommentsHash`(`[SCOPE-RECONCILED]` 코멘트), `latestCommentHash`, `commentsHash`, `prHash`)는 무엇이 바뀌어 재호출됐는지 보기 위한 진단용이다. | 항상 on(REDUCE 와 함께) |
| (c) 실패 백오프 | 호출 실패·빈 응답·항목 파싱 실패는 `checklist-shadow-failures.jsonl` 에 한 줄 남기고, 같은 `(isn, source)` 는 백오프 시간 동안 다시 부르지 않는다. 판정 기록(`checklist-shadow.jsonl`)에는 섞지 않는다. | 360분 |

환경변수(모두 선택): `GISSUE_CHECKLIST_SHADOW_REDUCE=off`(축소 전체 끄기 = 종전 동작: 매 틱 호출, 캐시·스킵·상한 없음), `GISSUE_CHECKLIST_SHADOW_TTL_HOURS`(0=TTL 스킵 끔), `GISSUE_CHECKLIST_SHADOW_MAX_PER_TICK`(0=끔), `GISSUE_CHECKLIST_SHADOW_MAX_PER_HOUR`(0=끔), `GISSUE_CHECKLIST_SHADOW_FAIL_BACKOFF_MIN`(0=끔), `GISSUE_CHECKLIST_SHADOW_DIR`(로그 폴더 재지정, 테스트용).

기록 방식: 로그 폴더가 없으면 만들고, BOM 없는 UTF-8 한 줄 JSON 으로 추가한다. 여러 프로세스가 동시에 쓰면 .NET 이 두 번째 쓰기를 `IOException` 으로 거절하므로 짧게 재시도한다(최대 6회). 레코드 필드: `ts, isn, source, legacy, checklist, reason, items[], cached, inputHash, contentHash, scopeCommentsHash, latestCommentHash, commentsHash, prHash, model, promptVersion` (+ 캐시 적중 시 `reusedFromTs`). 판정 프롬프트(`Invoke-ChecklistJudge`)를 바꾸면 `$script:ChecklistJudgePromptVersion` 을 올려 캐시를 무효화한다.

저장물과 소비처: `scripts/gissue/logs/checklist-shadow.jsonl`(판정 기록)·`checklist-shadow-failures.jsonl`(실패 기록) — 둘 다 gitignore, 머신 로컬. 소비처는 롤아웃 판단(사람)이다. 호출량 효과: 종전에는 구룰이 같은 이슈를 되돌리려 하는 틱마다 1회씩 호출했으나(파싱 실패는 기록도 없어 매 틱 재시도), 이제 같은 `(isn, source)` 는 24시간에 1회 이하, 입력이 같으면 0회, 틱당 5회·시간당 20회로 상한이 있다.

Shadow 가 쌓이지 않던 원인(수정됨): `review-done-audit.ps1` 은 `pr-gate-sweep.ps1` 과 달리 `[Console]::OutputEncoding` / `$OutputEncoding` 을 UTF-8 로 고정하지 않아, `powershell -File` 직접 실행 시 판정 LLM(`claude -p` stdin 파이프)에 한글이 깨져 전달됐고 응답이 항목 형식을 지키지 못해 `Ok=$false`(기록 없음)로 끝났다(실측: 구룰 REVERT 판정 4건 모두 파싱 실패 → 고정 후 4건 모두 기록). 같은 입력을 쓰는 Live 판정에도 영향이 있었다.

회귀 테스트: `powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\tests\test-checklist-shadow-reduce.ps1` (캐시 적중/미적중, 입력 변경 시 재호출, TTL·틱·시간당 상한, 실패 백오프, 끄기, Live 불변, 동시 쓰기).

## 13-3-1) 증거 기반 PR 귀속 + 되돌림 게이트 (giip #4840/#4839)

"대응 PR 없음" REVIEW→READY 되돌림이 27건 이상 누적된 사고의 근본 수정입니다.

### 근본 원인 (두 가지가 섞여 있었다)

| 원인 | 내용 | 조치 |
|---|---|---|
| (a) 귀속 실패 | PR 탐색면이 **기대 head 브랜치(`bot/task-giip-<isn>`) 1개**에 묶여 있었다. 레포 목록 밖(제품 레포·다른 프로젝트 레포), 비규약 브랜치(`docs/giip-4219-…`), 수동 PR, 커밋 메시지에만 isn 이 있는 PR 을 전부 "PR 없음"으로 오판. | **증거 4면 탐색**(아래) |
| (b) 판정 실패 | PR 귀속은 맞는데 **진행 코멘트 형식 같은 사소한 사유**로 되돌려짐(giip #4839). | **체크리스트 게이트**(아래) |

### 증거 4면 탐색 (정본: `lib/pr-lookup.mjs`)

| 면 | 탐색 | 비고 |
|---|---|---|
| 브랜치명 | 규약 브랜치(`head:bot/task-giip-<isn>`, 조직 전 1회) + 레포 브랜치 열거(`gh api …/branches`) → isn 을 담은 브랜치 → `gh pr list --head` | **GitHub 검색은 브랜치명을 색인하지 않는다**(2026-11-11 실측) — 직접 열거해야 잡힌다 |
| PR 제목/본문 | `gh search prs --owner <org>` (조직 전 레포) | `prMatchesIsn` 로 재필터(본문 폴백은 "담당 이슈를 선언하지 않은 PR" 한정) |
| 커밋 메시지 | `gh search commits --owner <org>` → 커밋에 딸린 PR | 다른 이슈를 선언한 PR 은 참조로 보고 제외 |
| 이슈 코멘트의 PR 링크 | `Get-PrLinksFromText` + `Get-ValidatedPrLinks` | 기존 경로 유지 |

조직 목록은 레포 origin 에서 유도하고 `GISSUE_GH_ORGS` 로 보강할 수 있습니다. **조직의 모든 브랜치를 열거하지는 않습니다**(LowyShin 조직은 272개 레포 — 무한대 비용). 비용 가드: 로컬 후보가 **이 isn 을 선언한** PR 이면 조직 전 탐색을 건너뜁니다(비용 0).

### 되돌림 게이트

되돌림(REVERT)을 구룰이 **제안**하면, 되돌리기 전에 의뢰 체크리스트 판정을 수행하고 **미충족(UNFULFILLED)일 때만** 되돌립니다.

| 판정 | 동작 |
|---|---|
| 판정 실패 / 파싱 실패 | **전이 없음** — 근거 없이 되돌리지 않는다 |
| KEEP(전 항목 충족) | 되돌리지 않음(코멘트도 남기지 않음 — 틱마다 쌓이지 않게) |
| HOLD(근거 부족) | 보류. 필요한 증거 코멘트 1회만 |
| REVERT(미충족 있음) | **체크리스트 코멘트(`## 의뢰 체크리스트 판정`)를 먼저** 남기고 READY 전이 |
| 캡 초과 / 동일 미충족 반복 | 자동 되돌림 중단 + NEEDS_DECISION |

### 모드

`-PrGateMode Gated|Shadow|Legacy` (미지정이면 환경변수 `GISSUE_PR_GATE_MODE`, 그것도 없으면 **Gated**).

| 모드 | 귀속 | 되돌림 결정 |
|---|---|---|
| Gated(기본) | 증거 기반 | 체크리스트 게이트(UNFULFILLED 일 때만) |
| Shadow | 증거 기반 | 구룰이 결정(즉시 되돌림) + 신룰 결론만 기록(비교용) |
| Legacy | 증거 기반 | 구룰이 결정, 기록 없음 |

**비교 가능성**: Gated/Shadow 모두 구룰 결론(`legacy`)과 신룰 결론(`checklist`)을 `logs/checklist-shadow.jsonl` 에 **같은 스키마**로 남깁니다 → `compare-checklist-vs-legacy.ps1` 로 두 경로를 직접 비교할 수 있습니다.

> `-ChecklistMode Live`(기존 스위치)는 REVIEW 판정 전체를 체크리스트로 대체하는 경로로 그대로 유지됩니다.

## 13-4) 게이트 디바운스 — 작업 세션이 방금 움직인 이슈는 한 틱 미룬다 (giip 4300)

**문제**: 3회 누적 에스컬레이션(전 게이트 합산 캡, giip #2085/#2415)이 이슈가 실제로 작업 중이던 구간의 체크에도 가산돼,
세션의 정상 handoff(REVIEW 전이)와 게이트의 NEEDS_DECISION 강제 전이가 1분 4초 차로 레이스한 사고가 있었다.

**사양** (`scripts/gissue/gissue-gate-tally-lib.ps1` 의 `Get-IssueActivityDebounce`):

| 항목 | 내용 |
|---|---|
| 용도 | `pr-gate-sweep.ps1` / `review-done-audit.ps1` 가 이슈를 판정하기 전에, 마지막 **작업 코멘트**가 `-MinIdleMinutes`(기본 10) 이내인지 본다. |
| 활동에서 제외 | 게이트 자신의 코멘트(되돌림·에스컬레이션·감사·`[VERIFY-RUN]`/`[VERIFY-GATE]`·체크리스트 판정). 포함하면 게이트가 코멘트를 남길 때마다 스스로 디바운스를 연장한다(자기참조). `Test-GateOwnComment` 가 판정. |
| 동작 | Active 이면 **스트라이크 가산·되돌림·에스컬레이션·상태 전이를 모두 하지 않고** 로그(`[DEBOUNCE]`)만 남긴 채 다음 틱으로 미룬다. 작업 코멘트가 잠잠해지면 다음 틱에 정상 판정하므로 무한 미룸이 없다. |
| 적용 지점 | `pr-gate-sweep.ps1`: 이슈별 `$tally` 계산 직후 — 체크리스트 `Live` 경로와 구룰(Off/Shadow) 경로 **양쪽 모두 이 앞**이다. `review-done-audit.ps1`: `Invoke-AuditIssue` 의 코멘트 조회 직후(`-DiagnoseIsn` 진단 모드는 디바운스하지 않는다). |
| 끄기 | `-MinIdleMinutes 0`. |
| 저장·소비 | 저장물 없음(상태 비저장 — 판정은 매 틱 이슈 코멘트의 `regdate` 로 다시 계산). 소비처는 위 두 스크립트의 로그. |
| 테스트 | `scripts/gissue/tests/test-gate-debounce.ps1` |

범위 밖: 동시 세션이 같은 이슈를 중복 수행하는 문제(세션 간 작업 가시성)는 이 디바운스로 해소되지 않는다. 디바운스는 게이트가 활동 중인 이슈를 건드리지 않게 할 뿐, 세션 시작 시 같은 isn 의 활성 세션을 확인하는 지점은 별도 후속 이슈로 다룬다.
