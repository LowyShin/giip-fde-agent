# pr-gate-sweep.ps1 — PR 완료 게이트 강제 후처리 (giip #1077)
#
# 배경(giip #1077): run-gissue-claude.ps1 의 PR 완료 게이트("어느 레포든 PR이 안 됐으면
#   REVIEW 가 아니라 READY 로 되돌려 다음 :07 이 이어받게 함")는 지금까지 claude 프롬프트의
#   자유서술 지시였을 뿐이라, 세션(특히 MiniMax 엔진 세션)이 git commit/push/PR 단계에 도달하기
#   전에 조기 종료하면서 그 지시를 무시하고 이슈를 REVIEW 로 전이하면(#1042/#1074 사례) 아무도
#   재시도하지 않아 완전히 방치됐다([C]는 READY≥1h, [D]는 stale IN_PROGRESS, [G]는 Actionflow
#   코멘트 없는 REVIEW 만 대상이라 "PR 0개 REVIEW"는 어느 큐에도 안 걸림).
#
# 이 스크립트는 그 게이트를 자유서술이 아니라 "세션 종료 후 스크립트가 강제로 재검증"하는
#   후처리 단계로 승격한다. 각 :07 실행이 CSN 잡을 마친 뒤 이 스윕을 돌리면, REVIEW 큐 안에서
#   nested repo 에 대응 PR(브랜치 `bot/task-giip-<isn>`)이 하나도 없는 이슈를 찾아 READY 로
#   되돌린다 → 다음 :07 [C] 가 이어받아 PR 까지 완수한다. (이미 REVIEW 에 방치된 것도 매 실행
#   스윕으로 회수되므로 giip #1077 조치 3번의 "1회성 정리"도 이 스크립트가 상시 담당한다.)
#
# 안전 설계:
#   - REVIEW 만 대상. DONE 은 절대 건드리지 않는다(투자/조사/코멘트-답변으로 정당하게 PR 없이
#     DONE 되는 경우가 흔해, DONE 자동 재오픈은 위조-DONE 을 잡는 이득보다 오탐 피해가 크다).
#   - 무한 왕복 방지(loop guard): 2026-08-18 최초 도입 시엔 "이슈당 최대 1회"였으나, giip #2085
#     (2026-09-06)로 "최대 3회 캡 + 매 회 지시 강화"로 확장됐다(아래 giip #2085 절 참고).
#   - PR 존재 판정은 오탐(불필요한 되돌림)을 줄이기 위해 넉넉하게: 정확한 head 브랜치
#     `bot/task-giip-<isn>` 매치 OR 넓은 검색(`giip-<isn>`)에서 브랜치/제목이 그 isn 을 담으면
#     "PR 있음"으로 본다.
#
# 2026-08-18(giip #1210): 위 loop guard/PR 존재 판정은 "PR 이 존재하는가"만 확인할 뿐, 그 PR 이
#   실제로 신고된 증상을 고쳤는지, 진행/테스트/검증 코멘트가 프로토콜대로 남았는지는 전혀 검증하지
#   않는다는 구조적 허점이 실측됐다(giip #1195: 무관한 파일 3줄만 고친 PR #545 가 게이트 통과 /
#   giip #1208: PR #546 은 정상 병합됐지만 진행 코멘트가 이슈에 단 하나도 없이 REVIEW 로 감).
#   그래서 Test-IssueHasPr 가 true 인 이슈에 대해서만 이어서 두 단계를 추가한다(모두
#   gissue-audit-lib.ps1 에 정의):
#     1) scope-match — PR 의 실제 diff 와 이슈 content+코멘트를 경량 LLM(claude-haiku-4-5, 도구
#        접근 없는 순수 텍스트 판정)에 넘겨 MATCH/MISMATCH 를 받는다. MISMATCH 면 `[SCOPE-GATE-REVERT]`
#        마커로 REVIEW→READY.
#     2) comment-gate — scope-match 가 MATCH 인 경우에만, 이슈 코멘트 이력에 착수/테스트결과/
#        사용자검증방법 코멘트가 실제로 있는지 같은 방식으로 판정한다. 미충족이면
#        `[COMMENT-GATE-REVERT]` 마커로 REVIEW→READY(코드는 정상이니 코멘트만 보완하라는 취지 명시).
#   판정 호출이 실패/차단되면 안전하게 기존 동작(PR 있음 → REVIEW 유지)으로 폴백하고 WARN 로그만
#   남긴다(스케줄러를 절대 막지 않는다). 판정 호출 구현 패턴(플래그 조합/인젝션 방어/인코딩)은
#   giip #1204(PR #572)에서 이미 확립된 것을 그대로 재사용한다 — gissue-audit-lib.ps1 의
#   Invoke-GissueJudge 주석 참고.
#
# 2026-09-06(giip #2085): 위 세 게이트(PR-gate/scope-gate/comment-gate)의 loop guard를 "이슈당
#   1회"에서 Actionflow 테스트 게이트(run-gissue-claude.ps1, giip #1565 계열)와 동일한 "최대 3회
#   캡 + 매 회 지시 강화" 구조로 통일한다. 배경: 1회성 loop guard는 되돌림 코멘트에 판정 근거+보완
#   지시를 남기긴 하지만, 2번째부터는 같은 문제가 반복돼도 그냥 REVIEW 에 머물러 아무도 다시
#   봐주지 않는다 — 반대로 3회까지는 자동으로 재시도 기회를 주고, 그래도 안 되면 그때 사람에게
#   넘기는 쪽이 더 많은 경우를 자동으로 해소한다(사용자 확정, 2026-09-06 AskUserQuestion 옵션1).
#   구현:
#     - `Get-GateRevertAttemptCount`(gissue-audit-lib.ps1) 로 "이 마커+작성자 조합으로 지금까지
#       몇 번 되돌려졌는지"를 센다(기존 boolean 전용 `Test-AlreadyRevertedByMarker` 는 에스컬레이션
#       마커 존재 확인용으로 계속 쓴다).
#     - attempt(=기존 개수+1) <= 3 이면 되돌리고, 코멘트에 (a) 몇 번째 되돌림인지 (b) 이전 되돌림들의
#       판정 근거 요약(`Get-GateRevertHistorySummary`) (c) 이번 판정 근거 (d) 다음 작업자가 그대로
#       실행 가능한 구체 체크리스트(게이트별로 다른 기준)를 남긴다.
#     - attempt > 3(=기존 개수 >= 3) 이면 더 이상 되돌리지 않고 게이트별 `*-GATE-HUMAN-REVIEW` 마커로
#       "사람 확인 필요" 코멘트를 딱 1회만 남긴다(그 마커 존재 여부로 재입장 방지 — 같은 이슈를 매 :07
#       마다 다시 스윕해도 중복 코멘트가 쌓이지 않는다).
#   PR-gate 도 scope-gate/comment-gate 와 동일한 카운팅/에스컬레이션 헬퍼(`Invoke-GateEscalate`)를
#   공유하도록 통일했다 — 기존에는 PR-gate 만 별도의 `Test-AlreadyReverted`(boolean) 를 썼다.
#
# 2026-09-14(giip #2415): 두 가지가 추가됐다.
#   1차(PR #728) — `[NO-PR-REASON]` 마커: PR 이 존재할 수 없는 "보고형 이슈"는 마커 코멘트 1건으로
#     PR-gate/scope-gate 를 모두 생략한다(`Test-HasNoPrReasonMarker`, gissue-audit-lib.ps1).
#   2차(이 변경) — 에스컬레이션의 실제 상태전이 + 전체 합산 + 회차 이력:
#     (a) 1차 구현의 `Invoke-GateEscalate` 는 코멘트만 남기고 REVIEW 를 그대로 뒀다. 코멘트 본문엔
#         "NEEDS_DECISION 전환"이라 적혀 있었는데 실제 전이가 없어, 에스컬레이션된 이슈(csn=47 의
#         #2214/#2148/#2123/#1929)가 2026-09-06~09-14 내내 일반 REVIEW 이슈와 구분되지 않은 채
#         아무도 집어가지 않았다. 이제 코멘트 등록 후 실제로 REVIEW → `NEEDS_DECISION` 으로 전이한다
#         (`Set-IssueNeedsDecision`, 기존 `updateIssueStatus.ps1 -Actor -Reason` 경로 재사용).
#         이미 에스컬레이션 코멘트가 있는 이슈는 코멘트만 건너뛰고 전이는 수행하므로 기존 방치분도 회수된다.
#     (b) 누적 카운트에 `review-done-audit.ps1` 의 되돌림(`[REVIEW-AUDIT:REVERT]`)을 합산한다
#         (giip #2415 요구사항 원문: "review-done-audit 되돌림까지 합산"). 집계는
#         `Get-GateRevertTally`(gissue-gate-tally-lib.ps1)가 담당하며, 이미 조회한 코멘트 배열을 재사용해
#         게이트별 반복 API 호출도 함께 제거했다.
#     (c) 에스컬레이션 코멘트에 회차별 이력(시각 · 게이트명 · 사유 1줄)을 싣는다.
#
# 2026-08-15(giip #1123 조사 중 발견, 회귀 버그 수정): REVIEW 큐 조회 응답 파싱이 실제 API 응답
#   모양 `{"issues":[...]}` 의 `.issues` 프로퍼티를 확인하지 않고 있었다(array/.data/.Table 만 체크
#   → 전부 불일치 시 `@($response)`로 전체 응답객체 하나를 배열로 감싸 반환, 그 객체엔 `.isn`이 없어
#   이후 Where-Object 필터가 100% 무조건 0건으로 떨어짐). 즉 이 스크립트는 배포 이후 REVIEW 이슈가
#   실제로 몇 건 있었든 상관없이 "대상 REVIEW 이슈 없음"만 보고해왔을 가능성이 있다 — giip #1123 이
#   "REVIEW 큐가 비어있어 revert 경로가 한 번도 실관찰되지 못했다"고 적은 원인이 실은 "큐가 정말
#   비어 있었다"가 아니라 "이 파싱 버그로 항상 0건으로 보였다"였을 가능성을 배제할 수 없다. `.issues`
#   분기를 추가해 수정했다(review-done-audit.ps1 조사 중 실제 DONE 872건 응답으로 재현 확인).
#
# 사용:
#   # 스케줄러가 세션 종료 후 자동 호출(run-gissue-claude.ps1 Complete-Run 에서)
#   powershell -File pr-gate-sweep.ps1 -Csn 47 -Workdir "C:\...\giipprj" -ApiKey <SK>
#   # 수동/드라이런(되돌림 없이 판정만)
#   powershell -File pr-gate-sweep.ps1 -Csn 47 -Workdir "C:\...\giipprj" -ApiKey <SK> -DryRun
#   # 단일 이슈 PR 존재 진단(상태 변경 없음 — 테스트용)
#   powershell -File pr-gate-sweep.ps1 -Workdir "C:\...\giipprj" -DiagnoseIsn 1076
param(
    [int]$Csn = 0,
    [Parameter(Mandatory = $true)][string]$Workdir,
    [string]$ApiKey,
    [string]$MgmtDir,
    [string]$ApiBaseUrl = "https://giipfaw.azurewebsites.net/api",
    [int]$DiagnoseIsn = 0,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# ── [giip #2613] 이 실행의 AI 행위자(actor) 고정 ───────────────────────────────
# 배경(실측 2026-09-16): giip 코멘트 최근 30일 작성자 1위가 `lowyshin.giip` 3,385건이었다.
#   이건 사람 계정이다(tCorpUser usn=156). 코멘트 SP 가 dbo.lwGetUSNbyat(@ak) 로 작성자를 정하는데,
#   이 함수의 마지막 폴백이 "SK 가 가리키는 CSn 의 tCorpUserRel.isPay=1 사용자"라서, csn 스코프 SK 로
#   코멘트를 쓰면 전부 그 CSn 의 결제자(=사람)에게 귀속됐다. authorUsn 도 거의 전부 NULL 이라
#   사후에 "어느 프로세스가 썼는지"를 확인할 방법이 없었다.
# 이 한 줄이 두 경로를 동시에 덮는다(자식 프로세스는 환경변수를 상속받는다):
#   (1) giipdbmgmtaddIssueComment.ps1 (직접-DB INSERT) -> -Actor 폴백으로 authorUsn 을 채운다
#   (2) scripts/gissue/get-issue.sh --comment (giipfaw API) -> 이 주체의 AccessToken 으로 인증한다
# 주체 목록/명명 규칙: scripts/gissue/ai-actors.json, 절차: scripts/gissue/AI_ACTOR_ACCOUNTS.md
# PR 게이트 스윕도 :07 스케줄러 계열이다. author 라벨(gissue-pr-gate 등)은 멱등성 판정에 쓰이므로 유지한다.
$env:GIIP_ACTOR = 'ai.dp01.gissue-scheduler'

# [ENCODING][giip #1210 -DryRun 실측 중 발견] scope-match/comment-gate 판정(gissue-audit-lib.ps1의
# Invoke-GissueJudge)이 `$prompt | & claude -p ...` stdin 파이프로 한글이 대부분인 이슈 content/코멘트를
# 넘긴다. 이 스크립트는(run-gissue-claude.ps1 과 달리) Start-Job 없이 `powershell -File` 로 직접 실행되므로
# PowerShell 5.1 기본 콘솔 코드페이지(949)로 인코딩되어 claude 가 "ENCODING_ERROR" 로 응답하는 것을 csn 47
# -DryRun 실행에서 실측했다(giip #1204 버그 B와 동일 원인 계열). run-gissue-claude.ps1 상단과 동일하게
# UTF-8 로 명시 고정한다.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
if (-not $MgmtDir) { $MgmtDir = Join-Path $Workdir 'giipdb\mgmt' }

# giip #2085: 모든 게이트(PR-gate/scope-gate/comment-gate) 공통 캡. Actionflow 테스트 게이트와 동일값.
$MaxGateRevertAttempts = 3

$RevertMarker = '[PR-GATE-REVERT]'
$RevertAuthor = 'gissue-pr-gate'
$RevertEscalatedMarker = '[PR-GATE-HUMAN-REVIEW]'

# giip #1210: PR 존재 확인(Test-IssueHasPr) 뒤에 이어지는 두 단계 추가 판정용 마커/작성자.
$ScopeRevertMarker = '[SCOPE-GATE-REVERT]'
$ScopeRevertAuthor = 'gissue-scope-gate'
$ScopeEscalatedMarker = '[SCOPE-GATE-HUMAN-REVIEW]'
$CommentRevertMarker = '[COMMENT-GATE-REVERT]'
$CommentRevertAuthor = 'gissue-comment-gate'
$CommentEscalatedMarker = '[COMMENT-GATE-HUMAN-REVIEW]'

# PR-존재 판정(Get-NestedRepoPaths/Test-IssueHasPr) + 코멘트 조회(Get-IssueComments) +
# 되돌림 시도횟수 카운팅(Get-GateRevertAttemptCount)/이력요약(Get-GateRevertHistorySummary) 공유 로직은
# gissue-audit-lib.ps1 로 분리됐다(giip #1123, review-done-audit.ps1 이 동일 로직을 재사용하기 위함).
. (Join-Path $PSScriptRoot 'gissue-audit-lib.ps1')
# giip #2415(2차 보완): 게이트 되돌림 "전체 합산" 집계기(review-done-audit 되돌림 포함) +
# 회차별 이력(시각/게이트/사유). 이미 조회한 코멘트 배열만 넘기면 되므로 추가 API 호출이 없다.
. (Join-Path $PSScriptRoot 'gissue-gate-tally-lib.ps1')

function Write-SweepLog($msg) {
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Write-Output "[$ts] [pr-gate-sweep] $msg"
}

# 공통 되돌림 실행기(giip #1210, giip #2085 로 attempt/history 파라미터 추가) — REVIEW→READY, note
# 코멘트, DryRun 로그만. 마커/작성자/본문/로그 라벨은 각 게이트가 넘긴다.
function Invoke-GateRevert($isn, $marker, $author, $note, $logLabel) {
    if ($DryRun) {
        Write-SweepLog "[DRYRUN] REVERT isn=$isn REVIEW→READY ($logLabel)"
        return
    }
    $tmp = Join-Path $env:TEMP ("gissue_{0}_note_{1}_{2}.txt" -f $author, $isn, [guid]::NewGuid().ToString('N'))
    try {
        [System.IO.File]::WriteAllText($tmp, $note, (New-Object System.Text.UTF8Encoding $true))
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $MgmtDir 'addIssueComment.ps1') -isn $isn -ContentFile $tmp -issuetype note -author $author 2>&1 | Out-Null
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $MgmtDir 'updateIssueStatus.ps1') -isn $isn -status "READY" -Actor $author -Reason "PR 게이트: $logLabel 판정으로 REVIEW→READY 강제 되돌림 (giip #1210/#2085)" 2>&1 | Out-Null
        Write-SweepLog "REVERTED isn=$isn REVIEW→READY ($logLabel) + note 등록"
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

# 에스컬레이션 상태전이(giip #2415 2차 보완, 2026-09-14): REVIEW → NEEDS_DECISION.
#
# 왜 필요했나: giip #2415 1차 구현(PR #728)은 에스컬레이션 코멘트만 남기고 상태를 그대로 REVIEW 로
#   두었다 — 코멘트 본문에는 "NEEDS_DECISION 전환"이라고 적혀 있는데 실제 전이는 없는 코드/문구 불일치.
#   그 결과 csn=47 의 에스컬레이션된 이슈들(#2214/#2148/#2123/#1929)이 2026-09-06~09-14 내내 REVIEW 에
#   남아 일반 REVIEW 이슈와 구분되지 않았고, 사람도 봇도 집어가지 않았다. NEEDS_DECISION 은 "자동화가
#   더 할 일이 없고 사람의 직접 판단만 남은 상태" 전용 버킷이며(giip #2374, giipdb SPEC §3) 자동 처리
#   큐(Get-GissueIssueQueue)에서 배제되므로, 에스컬레이션의 의미와 정확히 일치한다.
#
# 전이 수단은 새로 만들지 않는다 — 이 파일의 Invoke-GateRevert 가 이미 쓰는
#   `giipdb/mgmt/updateIssueStatus.ps1 -isn -status -Actor -Reason` 경로를 그대로 재사용한다
#   (그 스크립트가 [ALWAYS COMMENT], giip #1211 로 상태전이 코멘트까지 항상 남겨 준다).
# $Reason 은 코멘트 본문(파일 경유)과 달리 커맨드라인으로 직접 넘어가므로, giip #2404 실측 사고와 같은
#   인자 파싱 붕괴를 막기 위해 큰따옴표/개행을 안전한 문자로 치환하고 길이를 제한한다.
function Set-IssueNeedsDecision($isn, $author, $gateLabel, $reasonLine) {
    if ($DryRun) {
        Write-SweepLog "[DRYRUN] STATUS isn=$isn REVIEW→NEEDS_DECISION ($gateLabel)"
        return
    }
    $reason = "게이트 누적 에스컬레이션($gateLabel): $reasonLine (giip #2415)"
    $safeReason = ($reason -replace '"', "'") -replace '\r?\n', ' '
    if ($safeReason.Length -gt 400) { $safeReason = $safeReason.Substring(0, 400) }
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $MgmtDir 'updateIssueStatus.ps1') -isn $isn -status "NEEDS_DECISION" -Actor $author -Reason $safeReason 2>&1 | Out-Null
    Write-SweepLog "STATUS isn=$isn REVIEW→NEEDS_DECISION ($gateLabel)"
}

# 공통 에스컬레이션 실행기(giip #2085 신설, giip #2415 2차 보완으로 상태전이/회차이력 추가):
# 되돌림이 $MaxGateRevertAttempts 회에 도달하면 더 이상 자동으로 되돌리지 않고,
#   (1) "사람 확인 필요" 코멘트를 $escalatedMarker 로 딱 1회만 남기고
#   (2) 상태를 REVIEW → NEEDS_DECISION 으로 전이한다.
# 이미 그 마커가 있으면(=코멘트는 이미 남음) 코멘트만 건너뛰고 상태전이는 그대로 수행한다 —
#   1차 구현 시절 코멘트만 남은 채 REVIEW 에 방치된 기존 이슈들도 다음 스윕에서 자동으로 회수된다.
#   (전이가 성공하면 이 이슈는 REVIEW 큐에서 빠지므로 다음 스윕에 다시 들어오지 않는다.)
function Invoke-GateEscalate($isn, $escalatedMarker, $author, $gateLabel, $reasonLine, $tally) {
    if (Test-AlreadyRevertedByMarker $isn $escalatedMarker $author $ApiKey $ApiBaseUrl) {
        Write-SweepLog "isn=${isn}: 이미 에스컬레이션 코멘트 있음($escalatedMarker, $gateLabel) → 코멘트는 생략하고 NEEDS_DECISION 전이만 수행(giip #2415 2차)."
        Set-IssueNeedsDecision $isn $author $gateLabel $reasonLine
        return
    }
    # giip #2415 요구사항 #2 "왕복 이력 요약(각 회차 시각·게이트명·사유 1줄)".
    # 주의: 이 본문에 되돌림 마커 원문을 넣으면 그 코멘트 자신이 다음 회차 카운트를 부풀리므로,
    # 이력은 게이트명(PR-gate/scope-gate/comment-gate/review-done-audit)으로만 표기한다.
    if ($tally) { $countsText = $tally.CountsText; $historyText = $tally.HistoryText; $totalText = "$($tally.Total)" }
    else { $countsText = '(집계 없음)'; $historyText = '  (집계 없음)'; $totalText = '?' }
    $note = @"
$escalatedMarker (판정 시각: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
gissue 스케줄러의 게이트들이 이 이슈를 누적 $totalText 회 되돌렸지만(캡 $MaxGateRevertAttempts 회) 여전히
같은 문제가 해소되지 않아, 더 이상 자동으로 REVIEW → READY 되돌림을 시도하지 않습니다.
상태를 **NEEDS_DECISION** 으로 전이합니다 — 자동화가 할 수 있는 일은 끝났고 **사람의 직접 판단만
남았습니다**(giip #2085 의 3회 캡 패턴 + giip #2374 NEEDS_DECISION 버킷, 전이 구현은 giip #2415).

이번 판정 게이트: $gateLabel
사유: $reasonLine

누적 되돌림 집계(게이트 합산, review-done-audit 되돌림 포함): 총 $totalText 회 — $countsText

왕복 이력(회차별 시각 · 게이트 · 사유):
$historyText

사람이 확인할 것:
- [ ] 위 회차 이력에서 같은 사유가 반복됐는가(=자동화가 고칠 수 없는 구조적 문제인가)
- [ ] 이 이슈가 애초에 PR 이 존재할 수 없는 보고형 이슈인가 → 그렇다면 `[NO-PR-REASON]` 으로 시작하는
      코멘트를 사유 한 줄과 함께 남기면 이후 게이트가 이 이슈를 되돌리지 않습니다(giip #2415).
- [ ] 실제로 남은 작업이 있으면 READY 로, 완료로 판단되면 DONE 으로 직접 전이해 주십시오.

(이 코멘트는 이슈당 1회만 남습니다. 상태전이는 실패 시 다음 스윕에서 재시도됩니다.)
"@
    if ($DryRun) {
        Write-SweepLog "[DRYRUN] ESCALATE isn=$isn REVIEW→NEEDS_DECISION + 사람 확인 필요 코멘트 ($gateLabel, 누적 $totalText 회: $countsText)"
        return
    }
    $tmp = Join-Path $env:TEMP ("gissue_{0}_escalate_{1}_{2}.txt" -f $author, $isn, [guid]::NewGuid().ToString('N'))
    try {
        [System.IO.File]::WriteAllText($tmp, $note, (New-Object System.Text.UTF8Encoding $true))
        & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $MgmtDir 'addIssueComment.ps1') -isn $isn -ContentFile $tmp -issuetype note -author $author 2>&1 | Out-Null
        Write-SweepLog "ESCALATED isn=$isn 사람 확인 필요 코멘트 등록 ($gateLabel, 누적 $totalText 회: $countsText)"
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
    Set-IssueNeedsDecision $isn $author $gateLabel $reasonLine
}

# ── PR-gate: "이 isn 에 대응하는 PR 이 아예 없음" 되돌림 ──
function Invoke-Revert($isn, $priorAttemptCount) {
    $attempt = $priorAttemptCount + 1
    $history = Get-GateRevertHistorySummary $isn $RevertMarker $RevertAuthor $ApiKey $ApiBaseUrl
    $note = @"
$RevertMarker (재검증 시각: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
이번이 ${attempt}번째 되돌림입니다(최대 $MaxGateRevertAttempts 회).
gissue 스케줄러의 PR 완료 게이트 강제 후처리(giip #1077, 3회 캡 구조는 giip #2085)가 이 이슈를
REVIEW → READY 로 되돌렸습니다.
사유: 이 이슈에 대응하는 PR(브랜치 bot/task-giip-$isn)이 담당 nested 레포 어디에도 없습니다.
세션이 코드 수정까지만 하고 커밋/push/PR 단계 전에 종료됐을 때(예: 엔진 조기 종료) 발생하는
"PR 미완료인데 REVIEW 방치" 패턴입니다.

이전 되돌림 이력(판정 근거 요약):
$history

다음 작업자가 그대로 실행 가능한 체크리스트:
- [ ] 이 isn 에 대응하는 브랜치 bot/task-giip-$isn(또는 동등한 브랜치)로 실제 커밋을 푸시했는가
- [ ] 그 브랜치로 담당 nested 레포에 실제로 PR 을 열었는가(gh pr create)
- [ ] gh pr list --head bot/task-giip-$isn --state all 로 PR 존재를 직접 재확인했는가
- [ ] 만약 이 이슈가 PR 이 필요 없는 설계 결정/조사/코멘트-답변형이면, 그 사유를 명시적으로
      코멘트에 남겼는가(그 경우 이 게이트가 다시 튕기지 않는다)

다음 :07 실행이 이어받아 위 체크리스트를 확인합니다. 최대 $MaxGateRevertAttempts 회를 초과하면 더
이상 자동으로 되돌리지 않고 REVIEW 유지 + 사람 확인 필요로 전환됩니다.
"@
    Invoke-GateRevert $isn $RevertMarker $RevertAuthor $note "PR 없음 (attempt=$attempt/$MaxGateRevertAttempts)"
}

# [giip #2504 요구사항 #3] 판정 코멘트에 "실제로 평가한 PR" 을 증거로 싣는다.
# 종전 되돌림 코멘트는 LLM 이 낸 diff 요약만 담고 있어서, 사람이 오탐을 확인하려면 매번 손으로
# `gh pr view` 를 돌려야 했다(실제로 giip #2504 의 `PR #()` 오탐은 그래서 하루 종일 발견되지 않았다).
# 이제 repo/슬러그/PR번호/상태/탐지경로/변경 파일 목록 + 같은 isn 에 매칭된 다른 PR 후보까지 적는다.
function Format-PrEvidence($prInfo, $prDiff) {
    $lines = @()
    $lines += "- 평가한 PR: **#$($prInfo.number)** $($prInfo.url)"
    $lines += "- 레포: $($prInfo.slug) (로컬 체크아웃: $($prInfo.repo))"
    if ($prInfo.state) { $lines += "- PR 상태: $($prInfo.state)" }
    if ($prInfo.headRefName) { $lines += "- head 브랜치: ``$($prInfo.headRefName)``" }
    if ($prInfo.how) { $lines += "- 탐지 경로: $($prInfo.how)" }
    $files = if ($prDiff -and $prDiff.files) { "$($prDiff.files)".Trim() } else { '' }
    if ($files) {
        $lines += "- 변경 파일 목록(이 판정의 실제 입력):"
        foreach ($f in ($files -split "`r?`n")) { if ($f.Trim()) { $lines += "    - $($f.Trim())" } }
    } else {
        $lines += "- 변경 파일 목록: (조회 결과 없음)"
    }
    $others = @($prInfo.all | Where-Object { $_ -and "$($_.number)" -ne "$($prInfo.number)" })
    if ($others.Count -gt 0) {
        $lines += "- 같은 이슈에 매칭된 다른 PR 후보(판정에는 쓰이지 않음):"
        foreach ($o in $others) { $lines += "    - #$($o.number) [$($o.state)] $($o.slug) — $($o.url)" }
    }
    return ($lines -join "`n")
}

# ── scope-gate: PR 이 신고된 증상과 무관/범위 이탈로 판정됨 ──
function Invoke-ScopeRevert($isn, $prInfo, $rationale, $priorAttemptCount, $prDiff) {
    $attempt = $priorAttemptCount + 1
    $history = Get-GateRevertHistorySummary $isn $ScopeRevertMarker $ScopeRevertAuthor $ApiKey $ApiBaseUrl
    $evidence = Format-PrEvidence $prInfo $prDiff
    $note = @"
$ScopeRevertMarker (재검증 시각: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
이번이 ${attempt}번째 되돌림입니다(최대 $MaxGateRevertAttempts 회).
gissue 스케줄러의 scope-match 판정 게이트(giip #1210, 3회 캡 구조는 giip #2085)가 이 이슈를
REVIEW → READY 로 되돌렸습니다.
사유: PR #$($prInfo.number)($($prInfo.url))의 실제 변경 내용이 이 이슈에서 신고된 증상과 무관하거나
신고 범위보다 훨씬 좁은/다른 것을 고친 것으로 판정되었습니다(giip #1195 실증 패턴 — 무관한 파일의
사소한 수정만으로 "해결됨" 처리되는 스코프 이탈 방지).

이번 판정이 실제로 본 것(증거, giip #2504):
$evidence

이전 되돌림 이력(판정 근거 요약):
$history

이번 판정 근거(LLM 판정 응답):
$rationale

다음 작업자가 그대로 실행 가능한 체크리스트:
- [ ] 신고된 증상(이슈 원문 인용)을 재현하는 코드 경로를 실제로 수정했는가
- [ ] 수정한 파일이 신고 범위와 무관한 파일이 아닌가(예: 관련 없는 설정/문서 몇 줄만 건드린 것은 아닌가)
- [ ] PR diff 가 이슈 content 및 코멘트에서 재정의된 완료조건(예: "## [SCOPE-RECONCILED]" 코멘트가
      있다면 그 재해석 기준)과 실제로 일치하는가
- [ ] 이전 시도와 다른 접근으로 고쳤다면, 왜 이전 판정이 MISMATCH 였고 이번엔 무엇이 달라졌는지를
      새 코멘트에 명시했는가

원래 신고된 증상을 실제로 다루는 수정으로 다시 진행한 뒤 새 PR(또는 같은 PR 갱신)을 내면 다음 :07
실행이 이어받아 재검증합니다. 최대 $MaxGateRevertAttempts 회를 초과하면 더 이상 자동으로 되돌리지
않고 REVIEW 유지 + 사람 확인 필요로 전환됩니다.
"@
    Invoke-GateRevert $isn $ScopeRevertMarker $ScopeRevertAuthor $note "scope-match MISMATCH (attempt=$attempt/$MaxGateRevertAttempts)"
}

# ── comment-gate: PR/코드는 정상이나 진행 코멘트 프로토콜 미충족 ──
function Invoke-CommentRevert($isn, $prInfo, $rationale, $priorAttemptCount) {
    $attempt = $priorAttemptCount + 1
    $history = Get-GateRevertHistorySummary $isn $CommentRevertMarker $CommentRevertAuthor $ApiKey $ApiBaseUrl
    $note = @"
$CommentRevertMarker (재검증 시각: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
이번이 ${attempt}번째 되돌림입니다(최대 $MaxGateRevertAttempts 회).
gissue 스케줄러의 comment-gate 판정(giip #1210, 3회 캡 구조는 giip #2085)이 이 이슈를
REVIEW → READY 로 되돌렸습니다.

**중요: PR/코드는 정상입니다 — 다시 고치라는 뜻이 아닙니다.** PR #$($prInfo.number)($($prInfo.url))이
실제로 존재하고, scope-match 판정도 이미 통과했습니다(=이 PR 이 신고된 증상을 실제로 다룬다는 뜻).
다만 이 이슈의 코멘트 이력에 [진행 코멘트 프로토콜]이 요구하는 착수/테스트결과/사용자검증방법 코멘트가
실제로 등록되어 있지 않은 것으로 판정되었습니다(giip #1208 실증 패턴 — 코드는 정상 병합됐지만 진행
코멘트가 하나도 없이 REVIEW 로 감).

이전 되돌림 이력(판정 근거 요약):
$history

이번 판정 근거(LLM 판정 응답):
$rationale

**코멘트 프로토콜만 보완하면 됩니다.** 다음 작업자가 그대로 실행 가능한 체크리스트:
- [ ] 착수(작업 시작)를 알리는 코멘트가 있는가
- [ ] 실제로 무엇을 테스트/재현했고 그 결과가 무엇이었는지 서술한 코멘트가 있는가
- [ ] 사람이 직접 검증할 수 있는 구체적 방법(URL/커맨드/화면 경로 등)을 서술한 코멘트가 있는가
- [ ] 위 세 가지가 형식적 나열이 아니라 실제 내용을 담고 있는가(예: "테스트함"처럼 결과 서술 없이
      선언만 하는 것은 불충분)

코드를 다시 고치거나 PR 을 다시 낼 필요 없이, 누락된 코멘트를 등록한 뒤 다시 REVIEW 로 전이하십시오.
최대 $MaxGateRevertAttempts 회를 초과하면 더 이상 자동으로 되돌리지 않고 REVIEW 유지 + 사람 확인
필요로 전환됩니다.
"@
    Invoke-GateRevert $isn $CommentRevertMarker $CommentRevertAuthor $note "comment-gate UNSATISFIED (attempt=$attempt/$MaxGateRevertAttempts)"
}

# ── 진단 모드: 단일 isn 의 PR 존재 여부만 출력(상태 변경 없음) ──
if ($DiagnoseIsn -gt 0) {
    $repos = Get-NestedRepoPaths $Workdir
    Write-SweepLog "진단: isn=$DiagnoseIsn, repos=$(@($repos | ForEach-Object { Split-Path -Leaf $_ }) -join ',')"
    $has = Test-IssueHasPr $DiagnoseIsn $repos
    Write-SweepLog "isn=$DiagnoseIsn hasPR=$has"
    return
}

# ── 스윕 모드 ──
if (-not $ApiKey) { throw "ApiKey(SK) 가 필요합니다 — REVIEW 큐 조회용." }
if ($Csn -le 0) { throw "Csn 이 필요합니다." }

$repos = Get-NestedRepoPaths $Workdir
Write-SweepLog "시작: Csn=$Csn, repos=$(@($repos | ForEach-Object { Split-Path -Leaf $_ }) -join ',')$(if($DryRun){' [DRYRUN]'})"

# REVIEW 큐 조회(direct API — listReviewIssues.ps1 과 동일 정규화).
$uri = "$ApiBaseUrl/giipIssues?status=REVIEW&csn=$Csn"
try {
    $response = Invoke-GiipApiGet $uri $ApiKey
} catch {
    Write-SweepLog "REVIEW 조회 실패: $($_.Exception.Message)"
    return
}
if ($response -is [array]) { $issues = $response }
elseif ($response.issues) { $issues = $response.issues }   # 실측 응답 모양(giip #1123 조사 중 발견) — {"issues":[...]}
elseif ($response.data) { $issues = $response.data }
elseif ($response.Table) { $issues = $response.Table }
else { $issues = @($response) }
$issues = @($issues | Where-Object {
    $csnValue = if ($_.cSn -ne $null) { $_.cSn } elseif ($_.csn -ne $null) { $_.csn } else { $null }
    (-not $_.status -or $_.status -eq 'REVIEW') -and ($csnValue -eq $Csn) -and $_.isn
})

if (@($issues).Count -eq 0) { Write-SweepLog "대상 REVIEW 이슈 없음 — 종료."; return }
Write-SweepLog "REVIEW 이슈 $(@($issues).Count)건 검사."

$reverted = 0; $keptHasPr = 0; $keptGuard = 0; $keptNoPrReason = 0
$scopeReverted = 0; $scopeGuard = 0; $scopeNoPrReason = 0; $commentReverted = 0; $commentGuard = 0; $gateWarn = 0
foreach ($iss in $issues) {
    $isn = [int]$iss.isn
    $comments = Get-IssueComments $isn $ApiKey $ApiBaseUrl
    $hasNoPrReason = Test-HasNoPrReasonMarker $comments
    # giip #2415(2차): 게이트 되돌림을 한 번에 전부 집계한다. 이전 구현은 게이트마다
    # Get-GateRevertAttemptCount 를 호출해 같은 코멘트 목록을 몇 번씩 다시 받아왔고(API 낭비),
    # review-done-audit 가 남긴 되돌림은 아예 세지 않았다. 이제 위에서 1회 조회한 $comments 만으로
    # 게이트별 횟수 + 전체 합계 + 회차 이력을 모두 얻는다.
    $tally = Get-GateRevertTally $comments

    if (-not (Test-IssueHasPr $isn $repos)) {
        # ── giip #2415: [NO-PR-REASON] 마커 감지 시 PR-gate 되돌림 생략 ──
        if ($hasNoPrReason) {
            $keptNoPrReason++
            Write-SweepLog "isn=${isn}: PR 없음 + [NO-PR-REASON] 마커 감지 — PR-gate 생략, REVIEW 유지(giip #2415)."
        } else {
            # ── giip #2415: 누적 3회 에스컬레이션(전 게이트 합산 + review-done-audit 되돌림 포함) ──
            $prGateAttemptCount = $tally.Counts['PR-gate']
            $totalAttempts = $tally.Total
            if ($totalAttempts -ge $MaxGateRevertAttempts) {
                $keptGuard++
                Invoke-GateEscalate $isn $RevertEscalatedMarker $RevertAuthor "PR-gate(PR 존재 판정)" "브랜치 bot/task-giip-$isn 에 대응하는 PR 이 어느 nested 레포에도 없는 상태가 누적 $totalAttempts 회($($tally.CountsText)) 되돌림 이후에도 해소되지 않았습니다." $tally
                Write-SweepLog "isn=${isn}: PR 없음, 누적 $totalAttempts 회($($tally.CountsText)) 되돌림으로 최대치 도달 → NEEDS_DECISION 에스컬레이션(코멘트는 최초 1회만)."
            } else {
                Invoke-Revert $isn $prGateAttemptCount
                $reverted++
            }
        }
        continue
    }
    $keptHasPr++

    # ── giip #2415: scope-gateEvaluate 전 [NO-PR-REASON] 마커 체크 ──
    if ($hasNoPrReason) {
        $scopeNoPrReason++
        Write-SweepLog "isn=${isn}: [NO-PR-REASON] 마커 감지 — scope-match 평가 생략, REVIEW 유지(giip #2415)."
    } else {

    # ── giip #1210: scope-match / comment-gate 2단계 추가 판정 (giip #2085 로 3회 캡 적용) ──
    # PR 이 존재하는 것으로 확인된 이슈에 대해서만 진행한다. 판정 호출 자체가 실패/차단되면
    # 안전하게 기존 동작(PR 있음 → REVIEW 유지)으로 폴백하고 WARN 로그만 남긴다(이슈 본문 명시 요구).
    $prInfo = Get-IssuePrInfo $isn $repos
    if (-not $prInfo) {
        $gateWarn++
        Write-SweepLog "isn=${isn}: PR 있음으로 판정됐지만 상세 조회 실패 → scope/comment 게이트 생략, REVIEW 유지(안전 폴백)."
        continue
    }
    # ── [giip #2504] 평가 대상 PR 번호 미확정 → 판정 자체를 하지 않는다 ──
    # 2026-09-14 사고: Get-IssuePrInfo 가 PS 5.1 ConvertFrom-Json 빈배열 함정으로 `number=''` 인
    #   가짜 객체를 돌려줬고, 바로 위 `-not $prInfo` 가드는 객체가 non-null 이라 그대로 통과했다.
    #   그 뒤 `gh pr view '' ...` 가 현재 체크아웃 브랜치의 PR diff 를 물어와 scope-match 가 그
    #   무관한 diff 로 MISMATCH 를 냈다 → csn 47 의 REVIEW 36건이 하루 만에 일괄 READY(`PR #()`).
    # 원칙: **PR 을 특정하지 못한 상태의 "무관하다" 판정은 근거가 없다.** 되돌리지 않고 REVIEW 를
    #   유지한 뒤 WARN 만 남긴다. 게이트를 약화시키는 게 아니다 — PR 번호가 정상 확정되면 아래
    #   scope-match 는 종전과 똑같이 동작하고 MISMATCH 면 그대로 되돌린다.
    # 이 가드는 Get-IssuePrInfo/Get-PrDiffSummary 안의 같은 검사와 중복이지만, 세 곳 중 어디가
    #   회귀해도 되돌림까지는 가지 않도록 의도적으로 남긴 다중 방어선이다.
    if (-not (Test-ValidPrNumber $prInfo.number)) {
        $gateWarn++
        Write-SweepLog "isn=${isn}: 평가 대상 PR 번호 미확정(number='$($prInfo.number)', repo=$($prInfo.repo)) → scope/comment 게이트 생략, REVIEW 유지(giip #2504 가드)."
        continue
    }

    $scopeAttemptCount = $tally.Counts['scope-gate']
    if ($scopeAttemptCount -ge $MaxGateRevertAttempts) {
        $scopeGuard++
        Invoke-GateEscalate $isn $ScopeEscalatedMarker $ScopeRevertAuthor "scope-gate(scope-match MISMATCH)" "scope-match MISMATCH 판정으로 인한 되돌림이 $MaxGateRevertAttempts 회 반복되어 더 이상 자동 재시도하지 않습니다." $tally
        Write-SweepLog "isn=${isn}: scope-gate 되돌림 $scopeAttemptCount 회로 이미 최대치 도달 → NEEDS_DECISION 에스컬레이션(코멘트는 최초 1회만, 재판정 생략)."
    } else {
        $issueDetail = Get-IssueDetail $isn $ApiKey $ApiBaseUrl
        $commentsText = ConvertTo-CommentsText $comments
        $prDiff = Get-PrDiffSummary $prInfo.repo $prInfo.number $prInfo.slug
        $issueContent = if ($issueDetail -and $issueDetail.content) { $issueDetail.content } else { '' }

        # giip #2119(1회차/#2070 패턴): PR diff 를 files/diff 둘 다 빈 문자열로만 받아오면(동시 checkout 충돌·
        # gh 조회 실패 등) LLM 은 판정 근거가 아예 없는데도 강제 이분 포맷 때문에 부정 쪽(MISMATCH)을 기본값으로
        # 낸다. 그런 근거 없는 판정으로 REVIEW→READY 를 되돌리지 않도록, diff 가 완전히 비면 LLM 호출을 생략하고
        # 안전 폴백(REVIEW 유지 + WARN 로그)한다.
        $hasPrDiffEvidence = ($prDiff -and (($prDiff.files -and $prDiff.files.Trim() -ne '') -or ($prDiff.diff -and $prDiff.diff.Trim() -ne '')))
        if (-not $hasPrDiffEvidence) {
            $gateWarn++
            Write-SweepLog "isn=${isn}: PR diff 를 files/diff 모두 빈 값으로만 받아옴(조회 실패/동시 checkout 충돌 추정) → scope-match 판정 생략, REVIEW 유지(안전 폴백)."
        } else {
            $scopeJudge = Invoke-ScopeMatchJudge $isn $issueContent $commentsText $prInfo $prDiff
            if (-not $scopeJudge.ok) {
                $gateWarn++
                Write-SweepLog "isn=${isn}: scope-match 판정 호출 실패/차단(exit=$($scopeJudge.exit)) → 안전 폴백, REVIEW 유지."
            } else {
                $scopeVerdict = Get-JudgeVerdict $scopeJudge.text 'MATCH' 'MISMATCH'
                if ($scopeVerdict -eq 'MISMATCH') {
                    # ── giip #2415: 누적 3회 에스컬레이션(이번 되돌림 예정분 +1 포함) ──
                    $totalAttempts = $tally.Total + 1
                    if ($totalAttempts -ge $MaxGateRevertAttempts) {
                        $keptGuard++
                        Invoke-GateEscalate $isn $RevertEscalatedMarker $RevertAuthor "누적 ${MaxGateRevertAttempts}회 초과(전체 게이트 합산)" "PR#$($prInfo.number) scope-match MISMATCH 되돌림 예정분 포함 누적 $totalAttempts 회(기존 $($tally.CountsText) + 이번 scope-gate 1회) 재시도 이후에도 해소되지 않아 NEEDS_DECISION 전환." $tally
                        Write-SweepLog "isn=${isn}: scope-match MISMATCH, 누적 $totalAttempts 회 >= $MaxGateRevertAttempts → NEEDS_DECISION 에스컬레이션(전체 합산)."
                    } else {
                        Write-SweepLog "isn=${isn}: scope-match MISMATCH → REVERT (평가 PR #$($prInfo.number) $($prInfo.slug), 상태=$($prInfo.state))."
                        Invoke-ScopeRevert $isn $prInfo $scopeJudge.text $scopeAttemptCount $prDiff
                        $scopeReverted++
                    }
                } elseif ($scopeVerdict -eq 'MATCH') {
                    Write-SweepLog "isn=${isn}: scope-match MATCH → comment-gate 판정 진행."
                    $commentAttemptCount = $tally.Counts['comment-gate']
                    if ($commentAttemptCount -ge $MaxGateRevertAttempts) {
                        $commentGuard++
                        Invoke-GateEscalate $isn $CommentEscalatedMarker $CommentRevertAuthor "comment-gate(진행 코멘트 프로토콜 미충족)" "착수/테스트결과/사용자검증방법 코멘트 미비 판정으로 인한 되돌림이 $MaxGateRevertAttempts 회 반복되어 더 이상 자동 재시도하지 않습니다." $tally
                        Write-SweepLog "isn=${isn}: comment-gate 되돌림 $commentAttemptCount 회로 이미 최대치 도달 → NEEDS_DECISION 에스컬레이션(코멘트는 최초 1회만, 재판정 생략)."
                    } else {
                        $commentJudge = Invoke-CommentGateJudge $isn $commentsText
                        if (-not $commentJudge.ok) {
                            $gateWarn++
                            Write-SweepLog "isn=${isn}: comment-gate 판정 호출 실패/차단(exit=$($commentJudge.exit)) → 안전 폴백, REVIEW 유지."
                        } else {
                            $commentVerdict = Get-JudgeVerdict $commentJudge.text 'SATISFIED' 'UNSATISFIED'
                            if ($commentVerdict -eq 'UNSATISFIED') {
                                # ── giip #2415: 누적 3회 에스컬레이션(이번 되돌림 예정분 +1 포함) ──
                                $totalAttempts = $tally.Total + 1
                                if ($totalAttempts -ge $MaxGateRevertAttempts) {
                                    $keptGuard++
                                    Invoke-GateEscalate $isn $RevertEscalatedMarker $RevertAuthor "누적 ${MaxGateRevertAttempts}회 초과(전체 게이트 합산)" "PR#$($prInfo.number) comment-gate UNSATISFIED 되돌림 예정분 포함 누적 $totalAttempts 회(기존 $($tally.CountsText) + 이번 comment-gate 1회) 재시도 이후에도 해소되지 않아 NEEDS_DECISION 전환." $tally
                                    Write-SweepLog "isn=${isn}: comment-gate UNSATISFIED, 누적 $totalAttempts 회 >= $MaxGateRevertAttempts → NEEDS_DECISION 에스컬레이션(전체 합산)."
                                } else {
                                    Write-SweepLog "isn=${isn}: comment-gate UNSATISFIED → REVERT."
                                    Invoke-CommentRevert $isn $prInfo $commentJudge.text $commentAttemptCount
                                    $commentReverted++
                                }
                            } elseif ($commentVerdict -ne 'SATISFIED') {
                                $gateWarn++
                                Write-SweepLog "isn=${isn}: comment-gate 판정 응답 모호('$($commentJudge.text)') → 안전 폴백, REVIEW 유지."
                            } else {
                                Write-SweepLog "isn=${isn}: scope-match MATCH + comment-gate SATISFIED → REVIEW 유지([G] Actionflow 재검증 대상)."
                            }
                        }
                    }
                } else {
                    $gateWarn++
                    Write-SweepLog "isn=${isn}: scope-match 판정 응답 모호('$($scopeJudge.text)') → 안전 폴백, REVIEW 유지."
                }
            }
        }
    }  # end of scope-gate else (scope-gate max attempts or scope-gate proper)
    }  # end of else (hasNoPrReason) for PR-exists path
}  # end of foreach loop
Write-SweepLog "완료: PR없음-되돌림 $reverted, PR없음-NoPrReason유지 $keptNoPrReason, PR있음 $keptHasPr, 누적캡-NEEDS_DECISION에스컬레이션 $keptGuard, scope-되돌림 $scopeReverted, scope-NoPrReason유지 $scopeNoPrReason, scope-NEEDS_DECISION에스컬레이션 $scopeGuard, comment-되돌림 $commentReverted, comment-NEEDS_DECISION에스컬레이션 $commentGuard, 게이트경고(폴백) $gateWarn."
