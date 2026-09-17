# run-gate-escalation-recheck.ps1 — giip #2428: 3회 캡 도달(`*-GATE-HUMAN-REVIEW`) 이슈 자동 재판정 스윕
#
# 배경(giip #2428 이슈 본문):
#   pr-gate-sweep.ps1 은 PR/scope/comment 게이트가 누적 3회 되돌린 이슈에 `*-GATE-HUMAN-REVIEW`
#   코멘트를 1회 남기고 **거기서 끝난다**. 그 뒤로는 사람이 직접 열어보지 않는 한 아무도 이슈를 다시
#   읽지 않는다. 2026-09-06~09-14 동안 csn=47 에서 4건(#2214 #2148 #2123 #1929)이 그 상태로 묶여 있었고,
#   2026-09-14 오케스트레이터가 수동으로 하나씩 읽어보니 사람 판단이 실제로 필요한 것은 1건뿐이었다.
#   즉 "사람 확인 필요" 종착은 대부분 AI 가 읽으면 처리 가능한 것인데 읽는 주체가 없었을 뿐이다.
#
# 이 스크립트가 하는 일 (판정은 하지 않는다):
#   1) GIIPIssueGateEscalationList 로 `is_escalated=true` + 미종결 + **종착 상태**인 이슈를 수집한다.
#      종착 상태 = 아무도 손대고 있지 않은 상태 = `REVIEW` / `NEEDS_DECISION` (아래 [대상 상태] 참고).
#   2) 각 이슈의 코멘트를 읽어, 마지막 `*-GATE-HUMAN-REVIEW` 코멘트보다 **뒤에** `[GATE-RECHECK]`
#      마커가 이미 있으면 이번 회차는 건너뛴다(재왕복 방지 — 이 스윕 자신이 새 무한 왕복을 만들면 안 된다).
#   3) 아직 재판정되지 않은 이슈에는 `[GATE-RECHECK]` 작업 지시서 코멘트를 남기고 상태를 READY 로
#      되돌린다. 그러면 다음 :07 `run-gissue-claude.ps1` 실행의 [C] 단계
#      (listReadyIssues.ps1 -MinAgeMinutes 60 → "작업 지시서 코멘트가 있는 READY")가 그 이슈를 집어
#      **Claude/MiniMax 세션이 코멘트 이력을 읽고 실제 판정**을 수행한다.
#
# [대상 상태] — 회귀 재발 방지 (2026-09-14 실사고, giip #2428 1차 구현 버그)
#   1차 구현은 "미종결이면 전부"를 대상으로 삼아 **IN_PROGRESS 이슈까지 READY 로 되돌렸다**.
#   실제로 giip #2123 은 00:37 UTC 에 오케스트레이터가 IN_PROGRESS 로 전이하고 서브에이전트에 위임해
#   **작업이 진행 중**이었는데, 01:13 UTC 에 이 스윕이 READY 로 되돌려 살아있는 세션과 :07 스케줄러가
#   같은 이슈를 동시에 집어갈 수 있는 상태를 만들었다(같은 유형의 중복 처리 사고 이력: giip #2207/#2208,
#   두 세션이 같은 이슈를 처리해 PR 이 CONFLICTING 이 됨).
#   따라서 대상은 `-TargetStatuses` 화이트리스트로만 제한한다:
#     - 포함: `REVIEW`(게이트 3회 캡 종착 후 방치), `NEEDS_DECISION`(giip #2415 2차 보완 이후의 실제
#       에스컬레이션 종착 상태 — `pr-gate-sweep.ps1` 의 `Set-IssueNeedsDecision` 이 REVIEW→NEEDS_DECISION
#       으로 전이한다. 이걸 빼면 앞으로 생기는 에스컬레이션은 이 스윕이 영원히 못 집는다).
#     - 제외: `IN_PROGRESS`(누군가 작업 중 — 죽은 세션 회수는 [D] `listStaleInProgressIssues.ps1
#       -MinAgeMinutes 60` 경로의 소관이며 여기서 책임을 중복시키지 않는다), `READY`(이미 큐에 있음),
#       `PENDING`/`TESTED`/`DONE` 등 그 외 전부.
#
# [왜 상태를 READY 로 바꾸는가 — 코멘트만 남기면 안 되는 이유]
#   gissue 처리 큐는 별도 파일 큐가 아니라 giip 이슈 상태 그 자체다. `run-gissue-claude.ps1` 의 [C] 는
#   `listReadyIssues.ps1 -MinAgeMinutes 60` 으로 **READY** 만 집어간다. REVIEW 는 [G](Actionflow
#   재검증) 대상이고 NEEDS_DECISION 은 자동 처리 큐에서 아예 배제된다. 즉 코멘트만 남기고 상태를 그대로
#   두면 그 코멘트를 읽을 주체가 없어 이 스윕이 아무 일도 하지 않는 것과 같다. 상태 전이는 대상이 "아무도
#   작업하고 있지 않은 종착 상태"로 제한되어 있으므로 진행 중 작업을 가로챌 위험이 없다.
#
#   ※ 판정 로직을 이 PowerShell 안에 짜지 않는 것은 giip #2428 이슈 본문의 명시 요구사항이다 —
#     코멘트 이력 독해가 필요하므로 세션에 위임한다. 이 스크립트는 "대상 수집 + 중복 방지 + 큐 등록"까지만.
#
# 구조 관례는 선례(register-stale-pending-task.ps1 / GIIP_StalePending_Hourly)를 그대로 따른다:
#   등록 스크립트 + 실행 스크립트 2분할, audit-results/ 로그, idempotent 재등록, -Unregister 스위치.
#   (형제 파일 run-list-stale-review.ps1 은 2026-09-14 시점 파싱 불가 상태라 베이스로 쓰지 않았다 — giip #2429)
#
# ── 이 레포로의 이식 (giip #2645) ───────────────────────────────────────────────
#   원본은 lowyworkenv 판이다. 이식하며 바꾼 것은 **쓰기 경로**와 **경로 하드코딩** 두 가지뿐이고,
#   대상 선별·중복방지·MaxPerRun·작업지시서 본문 등 판정 로직은 그대로다:
#     · `giipdb/mgmt/addIssueComment.ps1` / `updateIssueStatus.ps1` (DB 직접) → `get-issue.sh`
#       `--comment-file` / `--status` (giipfaw API). 아래 Invoke-GissueIssueWrite 참고.
#     · 이 PC 전용 절대경로 폴백(giip-accounts.json, giipdb\mgmt) 제거 → 자기 레포 기준 상대경로만.
#
# 사용:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\run-gate-escalation-recheck.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts\gissue\run-gate-escalation-recheck.ps1 -Csn 47 -DryRun
param(
    # 0 이면 응답에 들어 있는 모든 CSN 을 대상으로 한다(API 가 csn 필터를 받지 않으므로 클라이언트에서 필터링).
    [int]$Csn = 0,
    # 미지정 시 <RepoRoot>/slack-bot/.secrets/giip-accounts.json 에서 해석한다(lib/resolve-sk.js).
    [string]$ApiKey = '',
    [string]$ApiBaseUrl = 'https://giipfaw.azurewebsites.net/api',
    # giipApi(giipfaw) Function Key. 미지정 시 $env:GIIP_AZURE_CODE → get-ak.sh 의 기본값 순으로 찾는다
    # (Resolve-GiipApiCode 참고). 여기에 리터럴로 적지 않는 이유는 두 가지다:
    #   (1) 같은 값이 레포 안에 두 벌 생기면 한쪽만 갱신되는 사고가 난다 — get-ak.sh 가 단일 출처다.
    #   (2) GitHub push protection 이 이 형태의 Azure Function Key 리터럴을 새 커밋에서 차단한다(실측).
    [string]$ApiCode = '',
    # 한 회차에 큐에 올릴 최대 건수(폭주 방지).
    [int]$MaxPerRun = 5,
    # 재판정 대상으로 삼을 이슈 상태 화이트리스트(쉼표 구분, 대소문자 무시). 파일 상단 [대상 상태] 참고.
    # IN_PROGRESS / READY 는 절대 기본값에 넣지 말 것 — 진행 중 작업 가로채기/중복 큐잉을 유발한다.
    [string]$TargetStatuses = 'REVIEW,NEEDS_DECISION',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# ── AI 행위자(actor) 고정에 대해 (giip #2613 / 이식 #2645) ─────────────────────
# 원본 lowyworkenv 판은 여기서 `$env:GIIP_ACTOR = 'ai.dp01.gissue-scheduler'` 를 세팅했다.
#   배경(실측 2026-09-16): 코멘트 SP 가 `dbo.lwGetUSNbyat(@ak)` 로 작성자를 정하는데 그 마지막 폴백이
#   "SK 가 가리키는 CSn 의 결제자" 라서, csn 스코프 SK 로 쓴 코멘트가 전부 사람 계정(`lowyshin.giip`)에
#   귀속됐다. 그 env 를 읽는 쪽은 lowyworkenv 의 `ai-actors.json` + `AI_ACTOR_ACCOUNTS.md` 기반
#   주체 테이블과 `giipdb/mgmt/addIssueComment.ps1` 인데, **이 레포에는 둘 다 없다**(실측 2026-09-17:
#   `scripts/gissue/ai-actors.json` 부재, `get-issue.sh` 에 GIIP_ACTOR 참조 없음).
#   값만 세팅해봐야 아무도 읽지 않으므로 여기서는 세팅하지 않는다. 코멘트 author 라벨
#   (`gissue-gate-recheck`)은 그대로 유지해 어느 스윕이 남긴 코멘트인지 본문으로 식별할 수 있게 한다.
#   이 레포에 AI 행위자 계정 테이블이 생기면 그때 같은 줄을 되살린다.

# [ENCODING] pr-gate-sweep.ps1 과 동일 — powershell -File 직접 실행 시 콘솔 코드페이지(949)로 한글이
# 깨지는 것을 막는다(giip #1204 계열).
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

$RecheckMarker  = '[GATE-RECHECK]'
$RecheckAuthor  = 'gissue-gate-recheck'
# pr-gate-sweep.ps1 의 $RevertEscalatedMarker / $ScopeEscalatedMarker / $CommentEscalatedMarker 를 모두 포괄.
# SPEC.md §누적 3회 초과 에스컬레이션이 언급하는 REVERT-GATE-HUMAN-REVIEW 표기도 함께 잡는다.
$HumanReviewPattern = '\[[A-Z\-]*GATE-HUMAN-REVIEW\]'
$RecheckPattern     = '\[GATE-RECHECK\]'

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot  = Split-Path (Split-Path $ScriptDir -Parent) -Parent

# Get-IssueComments / Invoke-GiipApiGet 재사용(읽기 전용). 이 라이브러리는 수정하지 않는다.
. (Join-Path $ScriptDir 'gissue-audit-lib.ps1')

$LogDir = Join-Path $ScriptDir 'audit-results'
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
$LogFile = Join-Path $LogDir ("gate-escalation-recheck-csn{0}.log" -f $Csn)

function Write-RecheckLog($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$ts] [gate-recheck] $msg"
    Write-Output $line
    try { Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8 } catch { }
}

# ── SK 해석 ──────────────────────────────────────────────────────────────
function Resolve-GissueApiKey($csn) {
    # giip-accounts.json 은 git 비추적 시크릿이라 배포마다 직접 채운다(.sample.json 을 복사).
    # 원본 lowyworkenv 판에는 "이 PC 의 메인 체크아웃" 절대경로 폴백이 있었지만, 다른 PC 에 clone 만
    # 해도 도는 것이 이 레포의 목적이므로 **자기 레포 루트 하나만** 본다(giip #2645).
    $accounts = Join-Path $RepoRoot 'slack-bot\.secrets\giip-accounts.json'
    if (-not (Test-Path -LiteralPath $accounts)) { throw "giip-accounts.json 을 찾을 수 없습니다: $accounts" }
    $resolver = Join-Path $ScriptDir 'lib\resolve-sk.js'
    # [주의] resolve-sk.js 는 csn 인자를 "아예 안 주었을 때"만 default 계정(봇 마스터 SK)으로 폴백한다.
    # 문자열 'null' 을 넘기면 `if (csnArg)` 가 truthy 로 걸려 채널 매칭에 실패하고 exit 1 이 된다
    # (2026-09-14 GIIP_GateEscalation_Hourly 첫 실행에서 LastTaskResult=1 로 실측). -Csn 0(전체 CSN 대상)
    # 일 때는 인자를 넘기지 않아 default SK 로 폴백시킨다 — 그 SK 는 sysadmin 이라 전 CSN 조회가 가능하다.
    if ($csn -gt 0) {
        $sk = (& node $resolver $accounts "$csn" 2>$null | Select-Object -First 1)
    } else {
        $sk = (& node $resolver $accounts 2>$null | Select-Object -First 1)
    }
    if (-not $sk) { throw "csn=$csn 에 대한 SK 해석 실패(resolve-sk.js)" }
    return "$sk".Trim()
}

# ── giipApi Function Key 해석 ─────────────────────────────────────────────
# 우선순위: -ApiCode 인자 → $env:GIIP_AZURE_CODE → get-ak.sh 의 기본값.
# get-ak.sh 29행이 `API_CODE="${GIIP_AZURE_CODE:-<기본값>}"` 형태로 단일 출처를 들고 있다.
function Resolve-GiipApiCode {
    param([string]$Explicit)
    if ($Explicit) { return $Explicit }
    if ($env:GIIP_AZURE_CODE) { return $env:GIIP_AZURE_CODE }
    $akSh = Join-Path $ScriptDir 'get-ak.sh'
    if (Test-Path -LiteralPath $akSh) {
        $line = (Select-String -LiteralPath $akSh -Pattern 'GIIP_AZURE_CODE:-' | Select-Object -First 1)
        if ($line -and $line.Line -match 'GIIP_AZURE_CODE:-([^}"]+)') { return $Matches[1] }
    }
    throw 'giipApi Function Key 를 찾을 수 없습니다. -ApiCode 로 주거나 $env:GIIP_AZURE_CODE 를 설정하세요(기본 출처: scripts/gissue/get-ak.sh).'
}

# ── 쓰기 경로: 코멘트 등록 / 상태 전이 (giip #2645 이식) ──────────────────
# 원본 lowyworkenv 판은 `giipdb/mgmt/addIssueComment.ps1` + `updateIssueStatus.ps1` (DB 직접 INSERT)을
# 호출했고, 그 mgmt 디렉터리를 csn-projects.json 의 workdir + 이 PC 전용 절대경로 폴백으로 찾았다.
# 이 레포에는 DB 직접접속 수단이 없으므로, 정본 문서
# `docs/60-operations/hourly-issue-scheduler.md` §4 의 "혼용 이식 금지" 규정대로 이 레포에 실제로 있는
# API 도구 `scripts/gissue/get-issue.sh` 로 교체한다(`run-gissue-claude.ps1` 이 쓰는 것과 같은 경로).
#   · 코멘트: `--comment-file <UTF-8 파일>` — 한글/이모지 본문을 커맨드라인 리터럴로 넘기면 headless
#     실행 체인에서 시스템 기본 코드페이지로 mojibake 가 난다(giip #1030). 반드시 파일 경로로 넘긴다.
#   · 상태 전이: `--status <STATUS>` (제목/본문 보존 PUT).
# 둘 다 내부에 CSN 교차오염 방지 게이트(lib/check-csn.js, giip #1053)가 걸려 있어, 이 스윕이 다른
# CSN 의 이슈를 실수로 건드리면 쓰기 전에 exit 2 로 막힌다.
function Invoke-GissueIssueWrite {
    <#
        get-issue.sh 를 1회 호출한다. 성공(exit 0)이면 $true, 아니면 예외.
        $Arguments 예: @('--comment-file', 'C:\tmp\x.txt') / @('--status', 'READY')
    #>
    param(
        [Parameter(Mandatory = $true)][int]$Isn,
        [Parameter(Mandatory = $true)][int]$IssueCsn,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    $sh = Join-Path $ScriptDir 'get-issue.sh'
    if (-not (Test-Path -LiteralPath $sh -PathType Leaf)) { throw "get-issue.sh 를 찾을 수 없습니다: $sh" }
    $bash = (Get-Command bash -ErrorAction SilentlyContinue).Source
    if (-not $bash) { throw 'bash 를 찾을 수 없습니다(Git for Windows 의 bash 가 PATH 에 있어야 합니다).' }

    $shPath = ($sh -replace '\\', '/')
    $out = & $bash $shPath "$Isn" "$IssueCsn" @Arguments 2>&1
    $rc = $LASTEXITCODE
    if ($rc -ne 0) {
        $tail = (($out | Select-Object -Last 3) -join ' | ')
        throw "get-issue.sh $($Arguments[0]) exit=$rc — $tail"
    }
    return $true
}

# ── 에스컬레이션 목록 조회 ────────────────────────────────────────────────
# giipApi 는 POST x-www-form-urlencoded 이며 SK 를 token/usertoken 으로 받는다(AK 불필요 — 2026-09-14 실측).
# PowerShell 5.1 의 Invoke-RestMethod 는 외부 API 호출에서 행(hang)이 관측되어 curl.exe 를 쓴다.
function Get-GateEscalationList($apiKey, $apiCode, $apiBaseUrl) {
    $uri = "$apiBaseUrl/giipApi?code=$apiCode"
    $raw = & curl.exe -s $uri `
        -H 'Content-Type: application/x-www-form-urlencoded' `
        --data-urlencode 'text=GIIPIssueGateEscalationList' `
        --data-urlencode 'jsondata={}' `
        --data-urlencode "token=$apiKey" `
        --data-urlencode "usertoken=$apiKey" 2>&1
    $text = ($raw | Out-String).Trim()
    if (-not $text) { throw 'GIIPIssueGateEscalationList 응답이 비어 있습니다.' }
    $parsed = $text | ConvertFrom-Json
    # 응답은 [[{...},{...}]] 형태(중첩 배열)로 온다. 단일 배열/단일 객체도 방어적으로 처리한다.
    if ($parsed -is [array] -and $parsed.Count -gt 0 -and $parsed[0] -is [array]) { return @($parsed[0]) }
    if ($parsed -is [array]) { return @($parsed) }
    return @($parsed)
}

# ── 마커 최신 시각 추출 ───────────────────────────────────────────────────
function Get-LatestMarkerDate($comments, $pattern) {
    $latest = $null
    foreach ($c in @($comments)) {
        $content = "$($c.content)"
        if (-not $content) { continue }
        if ($content -notmatch $pattern) { continue }
        $d = $null
        try { $d = [datetime]::Parse("$($c.regdate)", [Globalization.CultureInfo]::InvariantCulture) } catch { continue }
        if ($null -eq $latest -or $d -gt $latest) { $latest = $d }
    }
    return $latest
}

# ── 재판정 작업 지시서 본문 ───────────────────────────────────────────────
# giip #2428 이슈 본문의 4분기(a/b/c/d)를 판단 여지 없이 그대로 박아 넣는다.
function New-RecheckInstruction($isn, $gateType, $revertCount, $humanReviewDate) {
    $now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $hr  = if ($humanReviewDate) { $humanReviewDate.ToString('yyyy-MM-dd HH:mm:ss') } else { '(시각 미상)' }
    return @"
$RecheckMarker (재판정 큐 등록 시각: $now)
등록자: $RecheckAuthor (run-gate-escalation-recheck.ps1 / GIIP_GateEscalation_Hourly, giip #2428)

## 왜 이 코멘트가 달렸나
이 이슈는 gissue 게이트가 누적 $revertCount 회 되돌린 뒤 *-GATE-HUMAN-REVIEW (gate_type=$gateType,
마지막 에스컬레이션 $hr)로 종착해 **더 이상 아무도 읽지 않는 상태**였다. giip #2428 스윕이 이 이슈를
자동 재판정 대상으로 골라 READY 로 되돌렸다. 다음 :07 세션이 아래 절차를 그대로 수행한다.

## 이 이슈를 처리하는 세션이 할 일 (다른 판단 경로를 만들지 말 것)
먼저 이 이슈의 **전체 코멘트 이력을 시간순으로 읽는다**. 특히 *-GATE-REVERT / *-GATE-HUMAN-REVIEW
코멘트가 "무엇이 없어서" 되돌렸는지(PR 부재 / scope 불일치 / 코멘트 규약 위반)를 확인한다.
그 다음, 아래 4분기 중 **정확히 하나**를 골라 그 분기의 지시만 수행한다.

### (a) 선행/원본 이슈가 전부 종결됐거나 추적할 잔여 작업이 0 인 경우
→ 코멘트 첫 줄에 [NO-PR-REASON] 마커를 쓰고, 그 다음 줄부터 **왜 PR 이 존재할 수 없는지 / 왜 남은
   작업이 없는지** 구체적 사유(참조한 이슈 번호·PR 번호·확인한 실행 결과)를 쓴다. 그 뒤 상태를 DONE 으로
   전이한다. 마커만 쓰고 사유를 비우면 게이트가 무시하므로 반드시 사유 본문을 한 줄 이상 채운다.

### (b) 남은 조치가 "라이브 화면/API/DB 를 확인하는 것" 인 경우
→ **세션이 직접 확인한다.** 사람에게 넘기지 않는다. curl / gh / giipdb mgmt 스크립트 / 브라우저 검증 등
   실제 실행 결과를 코멘트에 인용하고(추측 금지, 배포 URL 추측 금지), 확인 결과에 따라 (a) 또는 (c) 로
   이어간다. 확인이 기술적으로 불가능하면 그 불가능 사유를 실행 로그와 함께 코멘트에 남긴다.

### (c) 진단은 끝났고 남은 게 구현뿐인 경우
→ 상태를 IN_PROGRESS 로 전이하고 **실제 구현에 착수**한다. 구현 범위가 이 이슈보다 크면 후속 이슈로
   분리 등록(register-issue.js)하고 이 이슈 코멘트에 그 이슈 번호를 명시한다. 구현 후에는 수정된 모든
   레포에 PR 을 내고 CI green 을 확인한 뒤 통상 절차대로 REVIEW 로 전이한다.

### (d) 되돌릴 수 없는 트레이드오프가 남은 경우에만
(진행 중 작업을 죽일 수 있는 정책 선택, 대외 배포 영향, 비용 발생, 데이터 파기 등)
→ 상태를 NEEDS_DECISION 으로 전이하고, 코멘트에 **사용자가 예/아니오로 답할 수 있는 질문 1개**만
   적는다. 예: "A 방식(기존 세션 강제 종료)으로 진행할까요? 예/아니오". "확인 바랍니다",
   "검토 부탁드립니다", "어떻게 할까요?" 같은 열린 문장은 금지한다. 선택지가 둘을 넘으면
   가장 유력한 안 하나로 좁혀 예/아니오 질문으로 만든다.

## 지켜야 할 제약
- 이 코멘트($RecheckMarker)는 재판정 1회를 위한 큐 등록이다. 같은 이슈에 대해 이 마커 뒤에
  판정 결과 코멘트를 반드시 1건 남겨라 — 남기지 않으면 다음 회차 스윕이 같은 이슈를 다시 큐에 올린다.
- 판정 결과 코멘트에는 .agent/rules/PROTOCOL_PROGRESS_COMMENT.md 규약대로 행위자/시각/상태 전이
  (예: "READY -> DONE")/로드한 role 파일 경로를 실제 값으로 적는다(자리표시자 문구 복사 금지).
- (a)~(d) 어느 분기든 **근거는 실행 결과로만** 인정한다
  (.agent/rules/42_completion_by_execution_evidence.md).
  PR 머지 여부는 "gh pr view --json files" 로 실제 diff 까지 확인한다.
- (a) 의 [NO-PR-REASON] 마커 규약은 .agent/rules/44_no_pr_reason_marker.md,
  (d) 의 NEEDS_DECISION 전이 규약은 .agent/rules/45_gate_cap_needs_decision.md 를 따른다.
"@
}

# ── 본 처리 ──────────────────────────────────────────────────────────────
$AllowedStatuses = @($TargetStatuses -split ',' | ForEach-Object { $_.Trim().ToUpper() } | Where-Object { $_ })
# 안전장치: 실수로든 의도로든 IN_PROGRESS/READY 가 화이트리스트에 들어오면 즉시 중단한다.
# (진행 중 세션 가로채기 = giip #2428 1차 구현이 실제로 일으킨 사고. 파일 상단 [대상 상태] 참고)
$ForbiddenStatuses = @('IN_PROGRESS', 'READY')
$violation = @($AllowedStatuses | Where-Object { $ForbiddenStatuses -contains $_ })
if ($violation.Count -gt 0) {
    throw "-TargetStatuses 에 금지 상태가 포함됐습니다: $($violation -join ', '). IN_PROGRESS 는 진행 중 작업(회수는 [D] listStaleInProgressIssues.ps1 소관), READY 는 이미 큐에 있는 이슈라 재판정 대상이 될 수 없습니다."
}

Write-RecheckLog "=== 시작 (Csn=$Csn, DryRun=$($DryRun.IsPresent), MaxPerRun=$MaxPerRun, TargetStatuses=$($AllowedStatuses -join '/')) ==="

if (-not $ApiKey) { $ApiKey = Resolve-GissueApiKey $Csn }
$ApiCode = Resolve-GiipApiCode $ApiCode
Write-RecheckLog "쓰기 경로=get-issue.sh (giipfaw API, DB 직접접속 없음)"

$all = @()
try {
    $all = Get-GateEscalationList $ApiKey $ApiCode $ApiBaseUrl
} catch {
    Write-RecheckLog "FAILED: 에스컬레이션 목록 조회 실패 — $($_.Exception.Message)"
    exit 1
}
Write-RecheckLog "목록 수신: 전체 $($all.Count) 건"

$escalated = @($all | Where-Object {
    ($_.is_escalated -eq $true -or $_.is_escalated -eq 1) -and
    -not ($_.is_closed -eq $true -or $_.is_closed -eq 1) -and
    ($Csn -le 0 -or [int]$_.cSn -eq $Csn)
})
Write-RecheckLog "에스컬레이션(is_escalated=true, 미종결): $($escalated.Count) 건"

# 상태 화이트리스트로 좁힌다. 제외 사유는 건별로 로그에 남긴다 — 왜 안 잡혔는지 추적 가능해야 한다.
$targets = @()
foreach ($e in $escalated) {
    $st = "$($e.status)".ToUpper()
    if ($AllowedStatuses -contains $st) { $targets += $e; continue }
    if ($st -eq 'IN_PROGRESS') {
        Write-RecheckLog "isn=$([int]$e.isn): status=IN_PROGRESS → 대상 제외(누군가 작업 중. 죽은 세션 회수는 [D] listStaleInProgressIssues.ps1 소관)"
    } elseif ($st -eq 'READY') {
        Write-RecheckLog "isn=$([int]$e.isn): status=READY → 대상 제외(이미 처리 큐에 있음)"
    } else {
        Write-RecheckLog "isn=$([int]$e.isn): status=$st → 대상 제외(TargetStatuses=$($AllowedStatuses -join '/') 에 없음)"
    }
}
Write-RecheckLog "재판정 후보(상태 필터 적용 후): $($targets.Count) 건"

$queued = 0
$skipped = 0
$failed = 0

foreach ($t in $targets) {
    $isn = [int]$t.isn
    $issueCsn = [int]$t.cSn
    if ($queued -ge $MaxPerRun) {
        Write-RecheckLog "isn=${isn}: MaxPerRun($MaxPerRun) 도달 → 이번 회차 보류(다음 회차에 처리)"
        continue
    }

    $comments = @(Get-IssueComments $isn $ApiKey $ApiBaseUrl)
    if ($comments.Count -eq 0) {
        Write-RecheckLog "isn=${isn}: 코멘트 조회 결과 0건 → 안전을 위해 스킵(중복 큐잉 방지 판정 불가)"
        $skipped++
        continue
    }

    $hrDate = Get-LatestMarkerDate $comments $HumanReviewPattern
    $rcDate = Get-LatestMarkerDate $comments $RecheckPattern

    if ($null -eq $hrDate) {
        Write-RecheckLog "isn=${isn}: *-GATE-HUMAN-REVIEW 코멘트를 찾지 못함 → 스킵(에스컬레이션 근거 불명)"
        $skipped++
        continue
    }
    if ($null -ne $rcDate -and $rcDate -ge $hrDate) {
        Write-RecheckLog "isn=${isn}: 이미 재판정 큐에 올라감($RecheckMarker $($rcDate.ToString('yyyy-MM-dd HH:mm:ss')) >= HUMAN-REVIEW $($hrDate.ToString('yyyy-MM-dd HH:mm:ss'))) → 스킵"
        $skipped++
        continue
    }

    $note = New-RecheckInstruction $isn "$($t.gate_type)" ([int]$t.revert_count) $hrDate

    if ($DryRun) {
        Write-RecheckLog "[DRYRUN] isn=${isn} (csn=$issueCsn, gate=$($t.gate_type), status=$($t.status)) → $RecheckMarker 코멘트 + READY 전이 예정"
        $queued++
        continue
    }

    $tmp = Join-Path $env:TEMP ("gissue_gate_recheck_{0}_{1}.txt" -f $isn, [guid]::NewGuid().ToString('N'))
    try {
        # 본문은 반드시 UTF-8 파일로 넘긴다(커맨드라인 리터럴은 mojibake — giip #1030).
        [System.IO.File]::WriteAllText($tmp, $note, (New-Object System.Text.UTF8Encoding $true))
        [void](Invoke-GissueIssueWrite -Isn $isn -IssueCsn $issueCsn -Arguments @('--comment-file', $tmp))
        [void](Invoke-GissueIssueWrite -Isn $isn -IssueCsn $issueCsn -Arguments @('--status', 'READY'))

        Write-RecheckLog "QUEUED isn=${isn} (csn=$issueCsn, gate=$($t.gate_type), revert_count=$($t.revert_count)) → $RecheckMarker 등록 + $($t.status) -> READY"
        $queued++
    } catch {
        Write-RecheckLog "FAILED isn=${isn}: $($_.Exception.Message)"
        $failed++
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

Write-RecheckLog "=== 종료: 큐등록 $queued 건 / 스킵 $skipped 건 / 실패 $failed 건 (후보 $($targets.Count) 건) ==="
if ($failed -gt 0) { exit 1 }
exit 0
