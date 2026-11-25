# 매시 이슈 처리 스케줄러 표준 스펙 — 등록·배포 상세

> 본문(정본): [hourly-issue-scheduler.md](./hourly-issue-scheduler.md) 에서 분리된 절
> 모음이다 (giip #6329 — 500라인 초과 분리). 절 번호는 본문과 동일하게 유지한다.
> 담는 절: §8 등록 스크립트 · §9 등록 확인 · §13 배포 절차 · §21 초기 설정(CSN repo 일괄 clone)

## 8) 등록 스크립트 상세 (`register-hourly-issue-scheduler.ps1`)

`scripts/register-hourly-issue-scheduler.ps1`은 이 문서 §2~§3 스펙을 그대로 구현하는, 파라미터화된
Windows Task Scheduler 등록/해제/확인 스크립트다. `-Action` 셋(기본값 `Status`) 3가지:

- **`Register`**: `-RepoRoot`(필수 — 이 스케줄러 스크립트 세트를 배치한 오케스트레이션 레포 루트,
  원본 배포는 `lowyworkenv`)를 받아 `-RunnerRelativePath`(기본
  `scripts/gissue/run-gissue-claude.ps1`)와 조합해 실제 러너 경로를 확인(`Test-Path`, 없으면 즉시
  에러)한 뒤, 다음을 등록한다:
  - **Action**: `powershell.exe -WindowStyle Hidden -NonInteractive -ExecutionPolicy Bypass -File
    "<runner경로>"`
  - **Trigger**: `-StartTime`(기본 `00:07:00`)에 1회 시작해 `-RepetitionMinutes`(기본 60분)마다
    반복. `-RepetitionDuration`을 `[TimeSpan]::MaxValue`로 주면 ISO8601 직렬화 시 Task Scheduler
    XML의 duration 상한을 넘어 등록 자체가 거부되므로(HRESULT 0x80041318, giip #1275 실측), 대신
    `New-TimeSpan -Days 3650`(약 10년)으로 사실상 무기한 반복을 구현한다.
  - **Settings**: `AllowStartIfOnBatteries`+`DontStopIfGoingOnBatteries`(배터리 전원과 무관하게
    실행/지속), `StartWhenAvailable`(예정 시각에 PC가 꺼져 있었으면 켜지는 즉시 실행),
    `MultipleInstances Parallel`(여러 인스턴스 동시 실행 허용), `ExecutionTimeLimit` 2시간.

    **러너 자신의 타임아웃은 `$RunTimeoutMin` = 105분이다** (`run-gissue-claude.ps1` 134행).
    Windows 쪽 `ExecutionTimeLimit`(2시간)보다 **15분 먼저** 만료되도록 일부러 낮춘 값이다 —
    이 15분 간격이 이 설정의 전부이므로 둘 중 하나만 바꾸지 말 것.

    **왜 120 이 아니라 105 인가(giip #1572, 2026-08-27 실측 사고)**: 원래 120분이었는데, 그러면
    Windows Task Scheduler 의 `ExecutionTimeLimit`(2시간)과 사실상 같아 여유가 전혀 없다. CSN47 잡이
    01:00:48 까지 정상적으로 작업하고 있었는데 01:07:00 에 **Windows 가 먼저 프로세스를 강제종료**해,
    스크립트 자신의 우아한 정리(`Complete-Run`, 락 해제)가 한 줄도 실행되지 못했고 `.lock` 파일이
    고아로 남았다. 즉 "러너가 자기 타임아웃으로 스스로 접는 경로"가 아예 도달 불가였다. 그래서
    러너를 Windows 보다 15분 먼저 만료시키도록 105 로 낮췄고, `ExecutionTimeLimit` 2시간은
    **"그 내부 정리마저 실패했을 때"의 최후 안전망**으로 남겨 두었다(제거하면 안 된다).

    **`MultipleInstances Parallel`로 바꾼 이유(giip #1562, 2026-08-26 실측 사고)**: 원래
    `IgnoreNew`였는데, csn 47(백로그 큼) 처리가 오래 걸려 16:07 인스턴스가 2시간 가까이 살아있는 동안
    17:07/18:07 정기 트리거가 "이전 인스턴스 실행 중"이라는 이유로 통째로 스킵됐다(이벤트 ID 322,
    18:07:05에 ExecutionTimeLimit 초과로 강제 종료 — 이벤트 ID 329). 오케스트레이터가 CSN별로
    Start-Job을 띄우고 전체 job이 끝날 때까지 기다리는 구조라, 하나의 태스크 인스턴스가 가장 느린 CSN
    하나 때문에 몇 시간씩 살아있으면 그동안 csn 47과 무관한 다른 모든 CSN(2, 33, 70335, 70374 등)의
    정기 처리까지 함께 멈췄다. 각 CSN은 이미 자체 파일 락(§9의 `gissue_csn<N>.lock`, 2시간 초과 시
    stale 자동제거)으로 "같은 CSN을 여러 인스턴스가 동시 처리"하는 것을 막고 있다는 전제 하에,
    `Parallel`로 바꿔 다음 트리거가 통째로 스킵되지 않도록 했다 — CSN별 중복 처리 방지는 계속 그
    파일 락이 담당한다.
  - **실행 계정**: 기본값은 현재 로그온 사용자(`$env:USERDOMAIN\$env:USERNAME`), `RunLevel Limited`.
    `-Password`를 넘기면 PSCredential로 비밀번호 인증 등록을 해 그 계정이 로그오프 상태여도(재부팅
    후 로그인 안 해도) 스케줄이 동작한다 — 넘기지 않으면 `Register-ScheduledTask`가 최초 등록 시
    대화형 자격증명 프롬프트를 띄울 수 있어 무인 등록(원격 세션 등)에서는 걸릴 수 있다.
  - **`-TaskName`**(기본 `GIIP_Gissue_Claude`): 같은 PC에 여러 배포를 동시에 등록하려면(예: 서로
    다른 오케스트레이션 레포/CSN 세트) 배포마다 고유한 이름을 지정해야 한다 — 기본값 그대로 두 번
    등록하면 `-Force`로 앞선 등록을 덮어쓴다.
- **`Unregister`**: 해당 `-TaskName`의 태스크를 확인 프롬프트 없이(`-Confirm:$false`) 제거. 이미
  없으면 에러 대신 안내 메시지만 출력(멱등).
- **`Status`**(기본값, `-RepoRoot` 불필요): `Get-ScheduledTask`+`Get-ScheduledTaskInfo`로 태스크
  이름·State·Enabled·등록된 Action 문자열·LastRunTime·LastTaskResult·NextRunTime을 한 번에 출력한다.

## 9) 등록 확인 방법

등록 스크립트의 `-Action Status`가 가장 빠른 확인 경로다:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\register-hourly-issue-scheduler.ps1 -Action Status -TaskName GIIP_Gissue_Claude
```

직접 표준 cmdlet으로 확인해도 동일하다:

```powershell
Get-ScheduledTask -TaskName GIIP_Gissue_Claude
Get-ScheduledTaskInfo -TaskName GIIP_Gissue_Claude | Select-Object LastRunTime, LastTaskResult, NextRunTime
```

`LastTaskResult`가 `0`이면 프로세스 자체는 정상 종료됐다는 뜻이지만(러너 내부는 CSN별로 try/catch로
감싸 개별 실패를 삼키므로 스크립트가 통째로 비정상 종료하는 경우는 드물다), **그것만으로 "이슈 처리가
실제로 진행되고 있다"를 확인했다고 보지 말 것** — 등록/기동 성공과 실제 큐 처리 진행은 별개다. 반드시
로그를 직접 열어 최근 사이클이 실제로 돌았는지 확인한다:

```powershell
Get-Content -Tail 20 -Encoding UTF8 .\scripts\gissue\logs\gissue_csn<CSN번호>.log
```

- `gissue_csn<N>.log`: `Write-Log`가 남기는 사람이 읽는 이벤트 로그. 정상 사이클이면 `START
  (cwd=...)`로 시작해(잡이 실제로 기동됐다는 뜻) 잡 종료 시 `DONE`(또는 타임아웃 시 `TIMEOUT`류
  메시지)으로 끝난다. `SKIP: ...`만 반복되면(workdir 없음/lock 미해제/스케줄러 비활성 등) 원인을
  그 SKIP 사유 문자열에서 바로 확인할 수 있다.
- `gissue_csn<N>.out.log`: claude/MiniMax 잡의 원시 stdout(프롬프트에 대한 실제 응답, 무엇을
  처리했는지 서술). 이슈가 실제로 처리됐는지 세부를 보려면 여기를 본다.
- `gissue_csn<N>.lock`: 실행 중 표시용 파일(내용은 PID). `$LockMaxAgeHr`(2시간)보다 오래됐으면 다음
  실행이 stale로 간주해 자동 제거하고 이어서 실행한다 — 사람이 수동으로 지울 필요는 보통 없다.

"최근 사이클이 실제로 새 코드로 돌았는지"까지 확인하려면(아래 §11 참고) 로그 타임스탬프가 최근
`git log`/`git pull` 이후인지 대조한다.

## 13) 배포 절차(신규 CSN/PC — 복사만으로 이식)

이 레포 자체가 이제 실행 가능한 구현체입니다(스펙 문서만이 아님). 새 프로젝트/PC에 이식하려면:

1. 이 레포(`giip-fde-agent`)를 그 PC에 clone(또는 이미 있으면 pull).
2. `scripts/gissue/csn-projects.json.example`을 `csn-projects.json`으로 복사 후 자기 CSN/워크디렉터리
   (+필요시 `restBranch`)만 채운다.
3. `slack-bot/.secrets/giip-accounts.sample.json`을 `giip-accounts.json`으로 복사 후 실제 SK를 채운다.
4. **안전 규칙 파일이 함께 복사됐는지, 프롬프트가 그것을 로드하는지 확인한다(§12, giip #2465)**:
   - `.agent/rules/41_issue_session_safety_index.md`와 그것이 링크하는 `42_`~`50_`,
     `.agent/rules/PROTOCOL_PROGRESS_COMMENT.md`가 이 clone 안에 실제로 존재하는지 확인한다
     (러너 스크립트만 골라 복사하는 이식은 여기서 걸린다).
   - 러너의 프롬프트 템플릿에 `[안전 규칙 로드]` 블록이 있고, 그것이 **정확히 1벌**인지 확인한다
     (§12-3의 카운트 명령). 2벌 이상이면 한쪽만 고쳐지는 사고의 조건이므로 먼저 합친다.
   - 복사만으로 이식되는 구조를 깨지 말 것 — 규칙을 다른 레포로 옮기거나 프롬프트에 본문을
     복제하면, 다음 이식 대상은 규칙 없이 도는 러너를 받게 된다.
5. `-DryRun -OnlyCsn <csn>`으로 먼저 실행해 워크디렉터리 인식·SK 해석·busy-check(BUSY 오판 없음)·엔진
   선택, 그리고 **프롬프트의 `{AGENT_REPO}` 치환 결과**(§12-4)까지 로그로 확인한다(실제 claude 미기동).

   **2~3단계를 건너뛰고 5단계를 먼저 실행해도 예외 스택트레이스가 나오지 않는다**(giip #2645):
   러너가 시작 직후 `Phase -3` 전제조건 preflight 를 돌려, 빠진 것을 행동지시로 알려준다.

   | 상태 | 러너의 반응 | 종료코드 |
   |---|---|---|
   | `csn-projects.json` 없음 | `[PREFLIGHT-FAIL]` + 복사할 명령·채울 항목·재실행 명령·이 절 링크 | 2 |
   | JSON 문법 오류 | `[PREFLIGHT-FAIL]` + 실패 사유 + 문법 힌트 | 2 |
   | `.example` 를 복사만 하고 값 미기입 | `[PREFLIGHT-FAIL]` + **어느 항목이 왜 잘못됐는지 항목별로** 제시 | 2 |
   | 일부 CSN 항목만 잘못됨 | `[PREFLIGHT-WARN]` + 그 항목만 건너뛰고 나머지는 정상 처리 | 0 |
   | `giip-accounts.json` 없음 | `[PREFLIGHT-WARN]` + 복사 명령(이슈 관련 단계는 전부 SKIP 됨) | 0 |
   | `node` / `gh` 미설치 | `[PREFLIGHT-WARN]` + 각 도구의 용도 | 0 |
   | bash 해석 성공 | `[PREFLIGHT] bash 해석됨: <절대경로>` (경고 아님) | 0 |
   | bash 후보 전부 실패 | `[PREFLIGHT-WARN]` + 설치 URL + 죽는 단계 명시 | 0 |

   설계 근거: 이 절의 5단계가 신규 PC 사용자의 **첫 명령**이다. 여기서 .NET 예외가 나오면
   "클론만으로 동일 작업 가능"이라는 이 배포의 전제가 깨진다. 따라서 **신규 clone 에 없는 것을 읽는
   모든 지점은 (a) 치명적이면 행동지시 + 비0 종료, (b) 아니면 행동지시 WARN 후 계속**이어야 한다 —
   조용한 예외/스택트레이스는 둘 다 아니다. 러너를 고칠 때 이 원칙을 깨지 말 것.

   검증도 같은 조건에서 해야 한다: "내 작업 폴더에서 돌아갔다"는 신규 clone 검증이 아니다.
   **gitignore 대상 설정 파일이 하나도 없는 상태**와 **채운 상태** 두 가지를 모두 돌려 확인한다.

   **bash 는 러너가 스스로 찾는다 — PATH 에 없어도 된다**(giip #2645). `powershell -File` 로 기동되는
   이 러너에서 `Get-Command bash` 가 실패하는 것은 **Git for Windows 기본 설치의 정상 상태**다:
   설치 프로그램은 `<Git>\cmd`(=`git.exe`)만 PATH 에 올리고 `bash.exe` 는 `<Git>\bin` 과
   `<Git>\usr\bin` 에 둔다. 그래서 러너는 PATH 존재 여부로 판정하지 않고 `Resolve-GissueBashExe`
   공용 함수로 아래 순서를 훑는다.

   | 순서 | 후보 |
   |---|---|
   | 1 | PATH 의 `bash`(사용자가 의도적으로 넣은 경우 최우선) |
   | 2 | `git.exe` 위치 역산 — `<Git>\bin\bash.exe`, `<Git>\usr\bin\bash.exe`(한 단계 위까지) |
   | 3 | `%ProgramFiles%` / `%ProgramFiles(x86)%` / `%LOCALAPPDATA%\Programs\Git` / `C:\Git` / `D:\Git` |

   Git 설치 위치가 어디든(기본 경로, `C:\Git`, scoop/winget, x86) 2번이 따라갑니다. 해석에 성공하면
   경고 대신 이 줄이 나옵니다(이 PC 실측):

   ```text
   [PREFLIGHT] bash 해석됨: C:\Program Files\Git\bin\bash.exe
   ```

   **모든 후보가 실패할 때만** 경고가 나오며, 그때는 설치 URL과 "어떤 단계가 죽는지"(이슈 코멘트 게시 /
   상태 전이 — 실패하면 이슈가 IN_PROGRESS·REVIEW 에 박혀 큐가 정체된다)를 함께 안내합니다.
   같은 해석 로직이 `verify-runner.mjs`(VERIFY-GATE)에도 들어가 있습니다 — 거기서 bash 를 못 찾으면
   ```` ```verify ```` 의 bash 블록이 전부 거짓 FAIL 이 되기 때문입니다.

   > 이전 판(PR #86 시점)은 이 절에 "시스템 PATH 에 `Git\bin` 을 추가하라"고 적혀 있었습니다.
   > 그 조치는 이제 **불필요**합니다. 러너가 스스로 찾습니다.
6. 문제 없으면 `register-hourly-issue-scheduler.ps1 -Action Register -RepoRoot <이 clone 경로>`로
   Windows 스케줄러에 등록한다(태스크 이름은 배포 대상마다 고유하게 `-TaskName`으로 지정).

   ⚠️ **태스크 등록은 반드시 정상 체크아웃에서 한다 — worktree 안에서 실행하면 거부된다.**
   등록기들은 `Register-ScheduledTask` 직전에 `task-target-guard.ps1` 의 3중 게이트를 통과해야 하는데,
   게이트 3 이 대상 `.ps1` 경로가 `\temp\worktrees\` 또는 `\.claude\worktrees\` 하위인지 검사해
   해당하면 등록을 중단한다(§15). worktree 경로를 태스크에 박으면 그 worktree 를 지우는 순간
   태스크가 존재하지 않는 파일을 가리키며 조용히 죽기 때문이다(giip #2431). 실제 거부 출력:

   ```text
   [TASK-GUARD][3/3][FAIL] 임시 worktree 경로(패턴 '\temp\worktrees\') 하위 — 등록 거부
   [TASK-GUARD][BLOCKED] <TaskName> 등록을 중단합니다(1건):
   ```

7. **(선택) 보조 시간별 스케줄러 5종을 등록한다.** 메인 태스크만으로도 동작하므로 필요할 때만
   등록하면 된다. 5종의 목록·주기·등록기 이름과 각 등록기의 파라미터는 **정본 유저가이드**
   [`./aux-hourly-schedulers.md`](./aux-hourly-schedulers.md) 를 따른다(§15 에 목록 요약).
   등록기도 6단계와 같은 3중 게이트를 쓰므로 **정상 체크아웃에서 실행해야 한다.**

   ```powershell
   # 5종 모두. 태스크 이름을 바꾸려면 각 등록기의 -TaskName 을 쓴다.
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\register-stale-pending-task.ps1
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\register-stale-review-task.ps1
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\register-audit-review-prs-task.ps1
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\register-gate-escalation-task.ps1
   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\register-slackbot-restart-task.ps1
   ```

   등록 전에 러너 5종을 직접 1회 돌려 보는 것을 권장한다(등록기는 파싱만 보고 실행 결과는 보지 않는다).
8. 등록 후 **한 사이클을 실제로 돌려** 세션 착수 코멘트의 로드 목록에 규칙 파일이 나타나는지
   확인한다 — 등록 성공 메시지나 `LastTaskResult=0`은 근거가 아니다(§9, `.agent/rules/42_`).

**주의**: 스케줄러가 처리할 workdir가 사람이 대화형으로 동시에 쓰는 작업 폴더와 같으면, `restBranch`를
지정해도 busy-check의 "다른 세션이 지금 쓰는 중" 신호와 실제 사람의 동시 작업을 근본적으로 구분할
수 없어, 사람이 작업 중인 워킹트리에 강제 언블록(stash+체크아웃)이 실행될 위험이 남는다. 대화형으로도
자주 쓰는 저장소라면, 스케줄러 전용 별도 clone을 workdir로 쓰는 것을 권장한다(원본 저장소와는 git
remote로만 연결된, 완전히 독립적인 워킹트리).

## 21) 초기 설정 — CSN의 GitHub repo 일괄 clone과 위치 저장 (giip 5783)

> 배경: 인스턴스가 giip-fde-agent를 내려받아 초기 설정할 때 CSN과 SK를 받는다. 그 시점에 콘솔 GitHub Actions 화면(/en/project/{CSN}/github)에 그 CSN으로 등록된 repo를 전부 내려받고 위치를 저장해, 그 CSN의 gissue를 처리할 때 내려받은 repo에서 작업하게 한다. 콘솔 실측(2026-11-19): 설정 1건 = repo 1개(owner/name) + PAT 1개, Active 플래그가 있고 대표 지정·기본 브랜치 필드는 없다.

### 21-1. 실행 진입점

```powershell
pwsh -NoProfile -File scripts/gissue/setup-csn-repos.ps1 -Csn <CSN> [-BaseDir <폴더>] [-DryRun]
```

- SK는 `-Sk`로 직접 주거나, 없으면 `slack-bot/.secrets/giip-accounts.json`에서 그 CSN의 SK를 찾는다(lib/resolve-sk.js).
- docker 인스턴스는 bootstrap-instance.sh가 `GIIP_SETUP_CSN` 환경변수가 있을 때만 이 진입점을 호출한다(선택 단계, 실패해도 부트스트랩은 계속).
- 조회 실패·설정 없음은 `[GHSETUP]` 로그만 남기고 종료 코드 0으로 끝낸다 — 초기 설정의 다른 절차를 막지 않는다(fail-soft).

### 21-2. 조회 계약 (giip 5782가 정본)

- `GET /api/giipGithubConfigs?csn=<n>`, 헤더 `x-api-key`에 그 CSN의 SK. AK에서 도출되는 CSN과 일치할 때만 그 CSN의 Active 설정 `[{ name, owner, repo, pat }]`를 반환한다(§19의 스코프드 byAK와 같은 패턴).
- 클라이언트 정본은 `lib/get-github-configs.js` — 응답에 실린 csn이 요청과 어긋나면 채택하지 않는다(scope_mismatch). 이 헬퍼의 stdout에는 PAT가 포함되므로 호출자는 출력을 로그에 남기지 않는다.

### 21-3. 위치 저장과 workdir 판정 (정본: lib/github-repos.ps1)

- clone 위치: 기준 폴더(`-BaseDir` > csn-projects.json 최상위 `repoBaseDir` > `~/giip-repos`) 아래 `<기준>/<CSN>/<repo명>`.
- 기록: csn-projects.json의 해당 CSN 항목에 `repos: [{ name, slug, path }]`를 병합 기록한다(다른 항목·키 보존, 원자적 교체 — §19의 캐시 병합과 같은 규칙).
- workdir 판정: 기존 workdir가 유효하면 유지한다(운영자 설정 우선). 없을 때 repo가 1개면 그 repo 경로, 여러 개면 워크스페이스 폴더(`<기준>/<CSN>`)를 workdir로 기록한다.

### 21-4. PAT 취급

- PAT는 clone 호출에 `http.extraHeader`로 1회만 주입한다 — 원격 URL(.git/config)에 남지 않는다.
- 이후 pull/push용 PAT는 `scripts/gissue/.secrets/github-pats.json`(gitignore 대상)에만 저장한다. 로그·리포트·이슈에 PAT 값을 쓰지 않는다.

### 21-5. 테스트

- `scripts/gissue/tests/test-github-configs.mjs` — 응답 해석(Active 필터, slug 해석, 스코프 방어, 빈 목록/404/500).
- `scripts/gissue/tests/test-github-repos.ps1` — clone 계획(slug 중복 제거), workdir 판정 4경우, csn-projects 병합 보존, PAT 저장, PAT 비노출 소스 단언.
