# worktree-safety.ps1 ScanRoot 가드 회귀 테스트 (giip 2668). 양방향: A = 차단되어야 함, B = 정상 기능은 유지되어야 함.
# 실측 사고: -RemnantScan 에 라이브 레포 루트를 ScanRoot 로 주면 그 레포의 .git/.agent/wiki/scripts 가 삭제 후보 67건으로 잡혔다.
# 실행: pwsh -NoProfile -File scripts/gissue/tests/test-scanroot-guard.ps1 [-SafetyScript <worktree-safety.ps1 경로>]
param([string]$SafetyScript)
$ErrorActionPreference = 'Stop'
if (-not $SafetyScript) { $SafetyScript = Join-Path $PSScriptRoot '../worktree-safety.ps1' }
. (Resolve-Path -LiteralPath $SafetyScript).Path

$fail = 0
function Check($name, [bool]$ok, $detail) {
    if ($ok) { Write-Output "[PASS] $name" } else { $script:fail++; Write-Output "[FAIL] $name — $detail" }
}
function New-Dir($p) { New-Item -ItemType Directory -Path $p -Force | Out-Null }

$base = Join-Path ([System.IO.Path]::GetTempPath()) ("scanroot_guard_" + [guid]::NewGuid().ToString('N'))
try {
    # ── 라이브 레포 루트 모양(giip 2660 실측과 같은 구성) ──
    $live = Join-Path $base 'giipprj'
    foreach ($d in '.git/objects', '.git/refs', '.git/hooks', '.agent/rules', '.agent/k_layer', 'wiki/specs', 'scripts/gissue', 'mgmt', '.github') { New-Dir (Join-Path $live $d) }
    Set-Content -LiteralPath (Join-Path $live '.agent/rules/x.md') -Value 'live'

    # A1: ScanRoot 가 라이브 레포 루트(.git 보유) → 후보 0건 + 거부
    $r = @(Get-GissueNoGitRemnant -ScanRoot $live -LiveWorkdir @() 3>$null)
    Check 'A1 라이브 레포 루트를 ScanRoot 로 주면 삭제 후보가 0건(.git/.agent/wiki 보호)' ($r.Count -eq 0) "후보 $($r.Count)건: $((($r | % { Split-Path $_.Path -Leaf }) -join ','))"
    $g = Test-GissueScanRootSafe -Root $live -LiveWorkdir @()
    Check 'A1b Test-GissueScanRootSafe 가 .git 보유 ScanRoot 를 거부' (-not $g.Safe) "Safe=$($g.Safe)"

    # A2: .git 이 없어도 csn-projects.json 의 라이브 작업 폴더와 같으면 거부
    $liveNoGit = Join-Path $base 'workdir-without-git'
    foreach ($d in 'docs/specs', 'tools/x') { New-Dir (Join-Path $liveNoGit $d) }
    $r = @(Get-GissueNoGitRemnant -ScanRoot $liveNoGit -LiveWorkdir @($liveNoGit) 3>$null)
    Check 'A2 라이브 작업 폴더(workdir)와 같은 ScanRoot 는 후보 0건' ($r.Count -eq 0) "후보 $($r.Count)건"
    $g = Test-GissueScanRootSafe -Root ($liveNoGit + '/') -LiveWorkdir @($liveNoGit)
    Check 'A2b 끝에 구분자가 붙어도 같은 경로로 인식해 거부' (-not $g.Safe) "Safe=$($g.Safe)"

    # A3: 관리 디렉터리(.agent/.github)는 후보에서 무조건 제외, 진짜 잔해는 유지
    $rootC = Join-Path $base 'wtroot'
    foreach ($d in 'hubX/.agent', 'hubX/.github', 'hubX/wt-leftover') { New-Dir (Join-Path $rootC $d) }
    Set-Content -LiteralPath (Join-Path $rootC 'hubX/wt-leftover/a.txt') -Value 'leftover'
    $r = @(Get-GissueNoGitRemnant -ScanRoot $rootC -LiveWorkdir @() 3>$null)
    $names = @($r | % { Split-Path $_.Path -Leaf })
    Check 'A3 .agent/.github 는 후보 제외' (($names -notcontains '.agent') -and ($names -notcontains '.github')) "후보: $($names -join ',')"

    # B1: 정상 구조(<루트>/<레포>/<워크트리>)에서는 진짜 잔해를 그대로 찾는다(기능 유지)
    Check 'B1 정상 ScanRoot 에서 .git 없는 잔해(wt-leftover)를 여전히 찾는다' ($names -contains 'wt-leftover') "후보: $($names -join ',')"
    $g = Test-GissueScanRootSafe -Root $rootC -LiveWorkdir @($liveNoGit)
    Check 'B2 정상 ScanRoot 는 거부되지 않는다' $g.Safe "Reason=$($g.Reason)"

    # B3: worktree(.git 파일 보유)는 후보가 아니다(기존 동작 유지)
    New-Dir (Join-Path $rootC 'hubX/wt-real')
    Set-Content -LiteralPath (Join-Path $rootC 'hubX/wt-real/.git') -Value 'gitdir: /nonexistent'
    $names2 = @((Get-GissueNoGitRemnant -ScanRoot $rootC -LiveWorkdir @() 3>$null) | % { Split-Path $_.Path -Leaf })
    Check 'B3 .git 파일이 있는 worktree 는 후보가 아니다' ($names2 -notcontains 'wt-real') "후보: $($names2 -join ',')"
}
finally { Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue }

Write-Output ''
if ($fail -eq 0) { Write-Output '결과: 전체 PASS' } else { Write-Output "결과: $fail 건 FAIL"; exit 1 }
