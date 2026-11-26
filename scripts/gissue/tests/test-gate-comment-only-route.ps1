# test-gate-comment-only-route.ps1 - comment-gate "코멘트 보충 전용 경로" 회귀 테스트 (giip #2648 결손 1 잔여)
#
# 왜 필요한가: pr-gate-sweep.ps1 의 comment-gate(진행 코멘트 프로토콜 미충족) 판정은 **PR/코드는 정상**
# 이다. 그런데 이 경로가 REVIEW→READY 되돌림을 쓰면, 이미 머지된 이슈가 "다시 구현할 대상"으로 만들어
# 큐 머리를 막는다(giip #2667 실측: READY 56건 중 31건이 그런 이슈로 밀려 착수조차 못 했다).
# 원본(lowyworkenv) PR #808 은 이 경로를 "상태는 REVIEW 유지 + 코멘트만 남김"으로 바꿨고, 이 저장소는
# 2026-11-26 에 그 동작(`Invoke-GateCommentOnly`)을 이식했다.
#
# 이 테스트가 고정하는 것:
#   (1) `Invoke-GateCommentOnly` 가 pr-gate-sweep.ps1 에 존재한다.
#   (2) 그 함수는 **코멘트만** 쓰고 **상태는 바꾸지 않는다**(`--status` 인자를 넘기지 않는다).
#   (3) comment-gate UNSATISFIED 호출부는 `Invoke-GateRevert`(되돌림)가 아니라
#       `Invoke-GateCommentOnly`(코멘트 보충 경로)를 호출한다.
#
# LLM/네트워크 없이 돈다 - 쓰기 수단(Invoke-IssueWrite)을 스텁으로 교체한다.
#
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-gate-comment-only-route.ps1

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$gissueDir = Split-Path -Parent $PSScriptRoot
$sweepPath = Join-Path $gissueDir 'pr-gate-sweep.ps1'

$fail = 0
function Assert($cond, $msg) {
    if ($cond) { Write-Host "  ok   $msg" }
    else { Write-Host "  FAIL $msg" -ForegroundColor Red; $script:fail++ }
}

Assert (Test-Path -LiteralPath $sweepPath) "pr-gate-sweep.ps1 이 존재한다 ($sweepPath)"

# ── 파싱: 함수 정의 본문을 AST 로 뽑는다(파일 전체를 dot-source 하면 최상위 코드가 실행된다) ──
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($sweepPath, [ref]$tokens, [ref]$parseErrors)
Assert (@($parseErrors).Count -eq 0) "pr-gate-sweep.ps1 이 파싱 에러 없이 로드된다 (에러 $(@($parseErrors).Count)건)"

function Get-FunctionText($ast, $name) {
    $fn = $ast.FindAll({
            param($n)
            $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name
        }, $true) | Select-Object -First 1
    if (-not $fn) { return $null }
    return $fn.Extent.Text
}

$commentOnlyText = Get-FunctionText $ast 'Invoke-GateCommentOnly'
Assert ($null -ne $commentOnlyText) 'Invoke-GateCommentOnly 함수가 pr-gate-sweep.ps1 에 정의되어 있다(giip #2667 코멘트 보충 경로)'
$commentRevertText = Get-FunctionText $ast 'Invoke-CommentRevert'
Assert ($null -ne $commentRevertText) 'Invoke-CommentRevert 함수가 pr-gate-sweep.ps1 에 정의되어 있다'

# ── (3) 호출부 배선: comment-gate UNSATISFIED 는 코멘트 보충 경로를 탄다 ──
if ($commentRevertText) {
    Assert ($commentRevertText -match 'Invoke-GateCommentOnly') 'comment-gate UNSATISFIED 경로가 Invoke-GateCommentOnly 를 호출한다'
    Assert ($commentRevertText -notmatch 'Invoke-GateRevert\s') 'comment-gate UNSATISFIED 경로가 Invoke-GateRevert(READY 되돌림)를 호출하지 않는다'
    Assert ($commentRevertText -match '코멘트 보충 전용 경로') 'comment-gate 코멘트 본문이 "코멘트 보충 전용 경로" 임을 밝힌다(READY 되돌림 아님)'
    Assert ($commentRevertText -notmatch 'REVIEW\s*→\s*READY\s*로\s*되돌렸습니다') 'comment-gate 코멘트 본문에 "REVIEW → READY 로 되돌렸습니다" 라는 거짓 서술이 없다'
}

# ── (2) 동작: 코멘트만 쓰고 상태는 바꾸지 않는다 ──
if ($commentOnlyText) {
    $script:issueWriteCalls = @()
    $script:sweepLogs = @()

    function Write-SweepLog($msg) { $script:sweepLogs += $msg }
    function Invoke-IssueWrite($isn, [string[]]$GetIssueArgs) {
        $script:issueWriteCalls += ,@($isn, @($GetIssueArgs))
        # 임시 코멘트 파일은 함수 종료 시 finally 에서 지워진다 — 스텁 안에서 내용물을 캡처한다.
        $a = @($GetIssueArgs)
        $i = [array]::IndexOf($a, '--comment-file')
        if ($i -ge 0 -and ($i + 1) -lt $a.Count) {
            $f = $a[$i + 1]
            $script:capturedFilePath = $f
            $script:capturedBytes = [System.IO.File]::ReadAllBytes($f)
            $script:capturedText = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)
        }
    }
    $DryRun = $false

    Invoke-Expression $commentOnlyText

    $note = "codement-only probe note"
    Invoke-GateCommentOnly 999999 '[COMMENT-GATE-REVERT]' 'gissue-comment-gate' $note '테스트 경로'

    Assert ($script:issueWriteCalls.Count -eq 1) "쓰기가 정확히 1회 발생했다 (실제 $($script:issueWriteCalls.Count)회)"

    $hasStatus = $false
    $commentFile = $null
    foreach ($call in $script:issueWriteCalls) {
        $args = @($call[1])
        foreach ($a in $args) { if ($a -eq '--status' -or "$a".StartsWith('--status=')) { $hasStatus = $true } }
        $idx = [array]::IndexOf($args, '--comment-file')
        if ($idx -ge 0 -and ($idx + 1) -lt $args.Count) { $commentFile = $args[$idx + 1] }
    }
    Assert (-not $hasStatus) '상태 전이(--status) 인자를 넘기지 않는다 — REVIEW 유지가 목적이다'
    Assert ($null -ne $commentFile) '코멘트 본문 파일(--comment-file)을 넘긴다'

    if ($commentFile) {
        Assert ($null -ne $script:capturedBytes) '코멘트 본문 임시 파일이 실제로 생성되어 쓰기 시점에 읽힌다'
        if ($null -ne $script:capturedBytes) {
            $bytes = $script:capturedBytes
            $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
            Assert $hasBom '임시 코멘트 파일은 UTF-8 with BOM 이다(PS 5.1 cp932 오독 방지)'
            Assert ($script:capturedText -match [regex]::Escape($note)) '임시 파일 내용물이 전달한 note 와 일치한다'
        }
        if (Test-Path -LiteralPath $commentFile) { Remove-Item -LiteralPath $commentFile -Force -ErrorAction SilentlyContinue }
    }
    Assert (@($script:sweepLogs | Where-Object { $_ -match 'REVIEW 유지' }).Count -ge 1) '로그에 "REVIEW 유지" 가 남는다(코멘트만 남긴 경로임을 기록)'
}

if ($fail -eq 0) {
    Write-Host '  PASS — comment-gate 코멘트 보충 전용 경로 정상(상태 전이 없음)'
    exit 0
}
Write-Host "  FAIL — $fail 건" -ForegroundColor Red
exit 1
