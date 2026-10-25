# run-repo-gates.ps1 — 저장소 자체 게이트 단일 진입점 (로컬 실행 = CI 실행)
#
# 왜 필요한가 (2026-10-24 CSN 70424 저장소 정비 세션 실측):
#   이 저장소에는 이미 "정본 게이트"가 있다 —
#     ① scripts/gissue/check-ps1-parse.ps1  (.ps1 65건 구문 + BOM 검사)
#     ② scripts/gissue/tests/test-*.ps1    (회귀 테스트 20건)
#     ③ scripts/gissue/tests/test-*.mjs    (회귀 테스트 5건)
#   그런데 **이 게이트가 CI 에 결선돼 있지 않았다.**
#   `.github/workflows/` 에는 windows-hook-doctor.yml 하나뿐이라,
#   2026-10-24 이전 정비 세션이 실측한 바로 그 결함들
#   (test-page-feedback-analyze.ps1 의 pwsh 하드코딩 / test-lang-check.mjs 의
#   셸 경유 커밋 본문 소실 / test-lang-qa.mjs 의 /tmp 하드코딩) 이
#   **실패한 채 main 에 유입된 뒤에야** 사람이 수동으로 돌려 발견했다.
#   → "이 게이트가 없으면 다음 결함은 main 에 유입된 채 발견되지 않는다."
#
# 이 스크립트의 목적 (rule 48 single_source_safety_predicate):
#   **판정 로직을 YAML 에 복붙하지 않는다.** CI 워크플로도 이 스크립트만 호출한다.
#   로컬에서 사람이 돌리는 명령과 CI 가 돌리는 명령이 **똑같은 코드**여야
#   "워크트리에서 green ≠ main 에서 green"(KNOW-005) 계열 사고가 재발하지 않는다.
#
# 단계:
#   1) 저장소 정본 게이트  : check-ps1-parse.ps1 -All  (자식 프로세스)
#   2) ps1 회귀 테스트 전수 : scripts/gissue/tests/test-*.ps1
#   3) mjs 회귀 테스트 전수 : scripts/gissue/tests/test-*.mjs
#   4) 마크다운 상대링크 스캔 : scripts/gissue/lib/relative-links.mjs
#
# 사용법:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/run-repo-gates.ps1
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/run-repo-gates.ps1 -SkipPs1Tests
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/run-repo-gates.ps1 -SkipMjsTests
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/run-repo-gates.ps1 -RepoRoot <저장소 루트>
#
# 종료코드: 0 = 전 단계 통과 / 1 = 실패 또는 검사 0건
#
# 주의 — 이 스크립트는 **읽기 전용**이다. 살아있는 체크아웃이나 D:\temp\worktrees 를
#   건드리지 않는다(각 회귀 테스트는 $env:TEMP 아래 임시 트리만 만든다).

param(
    # 단계 2(ps1 회귀 테스트)를 건너뛴다.
    [switch]$SkipPs1Tests,

    # 단계 3(mjs 회귀 테스트)를 건너뛴다.
    [switch]$SkipMjsTests,

    # 단계 4(마크다운 상대링크 스캔)를 건너뛴다.
    [switch]$SkipLinkScan,

    # 저장소 루트. 미지정이면 **이 스크립트 위치에서 2단계 상위**로 추정한다
    # (scripts/gissue → scripts → 저장소 루트) — 워크트리/공유 체크아웃 어디서 호출해도
    # 같은 저장소를 가리켜야 한다.
    [string]$RepoRoot = ''
)

# ⚠ NativeCommandError 로 죽지 않게 한다 — 자식 프로세스의 stderr 를 2>&1 로 받아야 한다.
$ErrorActionPreference = 'Continue'

# 이 PC 의 콘솔 기본 출력 인코딩은 cp932(shift_jis) 라서, 한글 출력이 '?' 로 뭉개진다.
# UTF-8 로 고정한다 (check-ps1-parse.ps1 과 동일한 처리, giip #2429).
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

# ── 상수: 기대 검사 건수 ────────────────────────────────────────────────────────
# 왜 있는가 (rule 42 — "검사기가 0개를 검사하고 PASS 를 반환하는 것"은 통과가 아니다):
#   회귀 테스트 파일이 **조용히 사라지면** 게이트는 "20건 전부 통과" 처럼 보이면서
#   실제로는 19건만 돌게 된다(2026-10-24 실측: .bak 으로 확장자를 바꿔 우회 시도).
#   그래서 발견된 파일 수가 기대값보다 **적으면 실패**로 처리한다.
#   테스트를 추가하면 이 수를 올리고, 제거하면(의도적 제거일 때만) 이 수를 내린다.
$ExpectedPs1TestCount = 20
$ExpectedMjsTestCount = 5

function Write-Gate([string]$Message) {
    Write-Output ("[REPO-GATE] " + $Message)
}

function Write-GateFail([string]$Message) {
    Write-Output ("[REPO-GATE][FAIL] " + $Message)
}

# ── 저장소 루트 확정 ───────────────────────────────────────────────────────────
# $PSScriptRoot 를 쓴다 — $MyInvocation.MyCommand.Path 는 `powershell -File` 로
# 호출했을 때 스크립트 경로가 비어 있을 수 있다(실측: scripts/gissue 가 빈 문자열로 나와
# Join-Path 이 "Path is empty string" 로 죽었다).
$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) {
    Write-GateFail "스크립트 위치를 확인할 수 없습니다 ($PSScriptRoot)"
    exit 1
}
if (-not $RepoRoot) {
    # scripts/gissue → scripts → 저장소 루트 (2단계 상위)
    $RepoRoot = (Split-Path -Parent (Split-Path -Parent $ScriptDir))
}
$resolvedRoot = Resolve-Path -LiteralPath $RepoRoot -ErrorAction SilentlyContinue
if (-not $resolvedRoot) {
    Write-GateFail "저장소 루트를 찾을 수 없습니다: $RepoRoot"
    exit 1
}
$RepoRoot = $resolvedRoot.Path

$TestsDir = Join-Path $RepoRoot 'scripts\gissue\tests'
$ParseGate = Join-Path $RepoRoot 'scripts\gissue\check-ps1-parse.ps1'
$LinkScanner = Join-Path $RepoRoot 'scripts\gissue\lib\relative-links.mjs'

Write-Gate "저장소 루트: $RepoRoot"
Write-Gate ("엔진: Windows PowerShell " + $PSVersionTable.PSVersion.ToString())

if (-not (Test-Path -LiteralPath $ParseGate -PathType Leaf)) {
    Write-GateFail "정본 게이트를 찾을 수 없습니다: $ParseGate"
    exit 1
}
if (-not (Test-Path -LiteralPath $TestsDir -PathType Container)) {
    Write-GateFail "회귀 테스트 디렉터리를 찾을 수 없습니다: $TestsDir"
    exit 1
}

$failures = New-Object System.Collections.Generic.List[string]
$checkedCount = 0
$linkScanCount = 0

# ── 단계 1: 저장소 정본 게이트 (check-ps1-parse.ps1 -All) ─────────────────────
Write-Gate "단계 1 — 저장소 정본 게이트 (check-ps1-parse.ps1 -All)"
$parseOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $ParseGate -All -RepoRoot $RepoRoot 2>&1
$parseExit = $LASTEXITCODE
foreach ($line in $parseOutput) { Write-Output ("    " + $line) }
if ($parseExit -ne 0) {
    Write-GateFail "정본 게이트(check-ps1-parse.ps1 -All) 실패 — exit $parseExit"
    $failures.Add("check-ps1-parse.ps1 -All (exit $parseExit)")
} else {
    Write-Gate "단계 1 통과 — 정본 게이트 exit 0"
}
$checkedCount++

# ── 단계 2: ps1 회귀 테스트 전수 ──────────────────────────────────────────────
$ps1Count = 0
if ($SkipPs1Tests) {
    Write-Gate "단계 2 SKIP — ps1 회귀 테스트 (-SkipPs1Tests 지정)"
} else {
    Write-Gate "단계 2 — ps1 회귀 테스트 전수"
    $ps1Tests = @(Get-ChildItem -LiteralPath $TestsDir -Filter 'test-*.ps1' -File -ErrorAction SilentlyContinue |
        Sort-Object Name | ForEach-Object { $_.FullName })
    $ps1Count = $ps1Tests.Count
    Write-Gate ("  발견한 ps1 테스트: {0}건 (기대 {1}건)" -f $ps1Count, $ExpectedPs1TestCount)
    if ($ps1Count -eq 0) {
        Write-GateFail "ps1 회귀 테스트 0건 — 검사기가 아무것도 검사하지 않았습니다 (rule 42)"
        $failures.Add("ps1 회귀 테스트 0건")
    } elseif ($ps1Count -lt $ExpectedPs1TestCount) {
        Write-GateFail ("ps1 회귀 테스트가 기대값보다 적습니다: {0}건 < {1}건 — 테스트 파일이 사라졌을 수 있습니다" -f $ps1Count, $ExpectedPs1TestCount)
        $failures.Add(("ps1 회귀 테스트 {0}건 (기대 {1}건)" -f $ps1Count, $ExpectedPs1TestCount))
    }
    foreach ($t in $ps1Tests) {
        $name = Split-Path -Leaf $t
        $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $t 2>&1
        $code = $LASTEXITCODE
        $checkedCount++
        if ($code -eq 0) {
            Write-Gate ("  PASS  {0}" -f $name)
        } else {
            Write-Gate ("  FAIL  {0} (exit {1})" -f $name, $code)
            foreach ($line in $out) { Write-Output ("      " + $line) }
            $failures.Add(("{0} (exit {1})" -f $name, $code))
        }
    }
}

# ── 단계 3: mjs 회귀 테스트 전수 ──────────────────────────────────────────────
$mjsCount = 0
if ($SkipMjsTests) {
    Write-Gate "단계 3 SKIP — mjs 회귀 테스트 (-SkipMjsTests 지정)"
} else {
    Write-Gate "단계 3 — mjs 회귀 테스트 전수"
    $mjsTests = @(Get-ChildItem -LiteralPath $TestsDir -Filter 'test-*.mjs' -File -ErrorAction SilentlyContinue |
        Sort-Object Name | ForEach-Object { $_.FullName })
    $mjsCount = $mjsTests.Count
    Write-Gate ("  발견한 mjs 테스트: {0}건 (기대 {1}건)" -f $mjsCount, $ExpectedMjsTestCount)
    if ($mjsCount -eq 0) {
        Write-GateFail "mjs 회귀 테스트 0건 — 검사기가 아무것도 검사하지 않았습니다 (rule 42)"
        $failures.Add("mjs 회귀 테스트 0건")
    } elseif ($mjsCount -lt $ExpectedMjsTestCount) {
        Write-GateFail ("mjs 회귀 테스트가 기대값보다 적습니다: {0}건 < {1}건 — 테스트 파일이 사라졌을 수 있습니다" -f $mjsCount, $ExpectedMjsTestCount)
        $failures.Add(("mjs 회귀 테스트 {0}건 (기대 {1}건)" -f $mjsCount, $ExpectedMjsTestCount))
    }
    # node 를 못 찾으면 **무음 PASS 금지** — 명확한 FAIL 로 끝낸다.
    # (이 저장소에서 "조용히 아무 일도 하지 않고 끝난" 도구가 이미 한 번 사고를 만들었다)
    $nodeCmd = Get-Command node -ErrorAction SilentlyContinue
    if (-not $nodeCmd) {
        Write-GateFail "node 를 찾을 수 없습니다 — mjs 회귀 테스트를 실행할 수 없습니다 (설치하지 말고 PATH/Node 설치를 확인하십시오)"
        $failures.Add("node 미설치 — mjs 회귀 테스트 미실행")
    } else {
        $nodePath = $nodeCmd.Source
        Write-Gate ("  node: {0}" -f $nodePath)
        foreach ($t in $mjsTests) {
            $name = Split-Path -Leaf $t
            $out = & $nodePath $t 2>&1
            $code = $LASTEXITCODE
            $checkedCount++
            if ($code -eq 0) {
                Write-Gate ("  PASS  {0}" -f $name)
            } else {
                Write-Gate ("  FAIL  {0} (exit {1})" -f $name, $code)
                foreach ($line in $out) { Write-Output ("      " + $line) }
                $failures.Add(("{0} (exit {1})" -f $name, $code))
            }
        }
    }
}

# ── 단계 4: 마크다운 상대링크 스캔 ─────────────────────────────────────────────
# 왜 필요한가 (2026-10-25 CSN 70424 저장소 정비 51차 세션 실측):
#   43~50차 정비 세션이 **매번 새로 짠 스캐너**로 상대링크를 스캔했다.
#   스캐너가 회차마다 달라 "미존재 링크 N건" 기준선이 11↔34 사이를 흔들었고,
#   "N건 = 스캐폴딩 A + 코드예시 B" 분류를 매 회차 사람이 손으로 해야 했다.
#   → 판정 로직을 저장소 정규본(`lib/relative-links.mjs`)으로 고정하고 게이트에 결선한다.
#   같은 스캐너를 쓰면 다음 회차의 기준선은 **이번 회차와 동일**하다.
if ($SkipLinkScan) {
    Write-Gate "단계 4 SKIP — 마크다운 상대링크 스캔 (-SkipLinkScan 지정)"
} else {
    Write-Gate "단계 4 — 마크다운 상대링크 스캔"
    if (-not (Test-Path -LiteralPath $LinkScanner -PathType Leaf)) {
        Write-GateFail "상대링크 스캐너를 찾을 수 없습니다: $LinkScanner"
        $failures.Add("상대링크 스캐너 없음")
    } else {
        $nodeCmd4 = Get-Command node -ErrorAction SilentlyContinue
        if (-not $nodeCmd4) {
            Write-GateFail "node 를 찾을 수 없습니다 — 상대링크 스캔을 실행할 수 없습니다 (설치하지 말고 PATH/Node 설치를 확인하십시오)"
            $failures.Add("node 미설치 — 상대링크 스캔 미실행")
        } else {
            $linkOut = & $nodeCmd4.Source $LinkScanner --repo-root $RepoRoot 2>&1
            $linkExit = $LASTEXITCODE
            foreach ($line in $linkOut) { Write-Output ("    " + $line) }
            $checkedCount++
            $linkScanCount = 1
            if ($linkExit -eq 0) {
                Write-Gate "단계 4 통과 — 실제 결함 0건"
            } else {
                Write-GateFail ("상대링크 스캔 실패 — exit {0} (결함 링크 있음 또는 검사 대상 0건)" -f $linkExit)
                $failures.Add(("상대링크 스캔 (exit {0})" -f $linkExit))
            }
        }
    }
}

# ── 판정 ───────────────────────────────────────────────────────────────────────
if ($checkedCount -eq 0) {
    Write-GateFail "총 검사 건수가 0건입니다 — 통과로 읽지 않습니다 (rule 42)"
    $failures.Add("총 검사 0건")
}

Write-Output ""
if ($failures.Count -gt 0) {
    foreach ($f in $failures) { Write-GateFail ("실패: " + $f) }
    Write-Gate ("결과: ps1 {0}건 / mjs {1}건 / 링크스캔 {2} / 실패 {3}건" -f $ps1Count, $mjsCount, $linkScanCount, $failures.Count)
    exit 1
}

Write-Gate ("결과: ps1 {0}건 / mjs {1}건 / 링크스캔 {2} / 실패 0건" -f $ps1Count, $mjsCount, $linkScanCount)
exit 0
