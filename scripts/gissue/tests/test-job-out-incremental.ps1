# [giip 4431 항목 3] 잡 출력 증분 보존 — Receive-Job -Keep 이 매번 전체 버퍼를 돌려줄 때 "아직 안 쓴
# 꼬리"만 골라 out.log 에 누적하되 **중복 없이** 쌓이는지, 그리고 잡이 Complete-Run 없이 끊겨도 직전까지
# 기록이 남는 배선인지 검증한다.
# 실행: powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-job-out-incremental.ps1
# 네트워크/파일 쓰기 없음. lib/job-out-tail.ps1 의 순수 함수와, 러너 소스의 배선 위치만 확인한다.
$ErrorActionPreference = 'Stop'
. (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../lib/job-out-tail.ps1')).Path

$fail = 0
function Check($name, [bool]$ok, $detail) {
    if ($ok) { Write-Output "[PASS] $name" } else { $script:fail++; Write-Output "[FAIL] $name - $detail" }
}

# ── (A) 첫 읽기: 전체 꼬리를 돌려주고 카운터를 전체 줄 수로 올린다 ──
$r = Split-GissueJobOutTail -AllLines @('a', 'b', 'c') -WrittenCount 0
Check 'A1 첫 읽기 3줄 전부 NewLines' (@($r.NewLines).Count -eq 3 -and ($r.NewLines -join ',') -eq 'a,b,c') "NewLines=$($r.NewLines -join ',')"
Check 'A2 카운터가 3 으로' ($r.WrittenCount -eq 3) "WrittenCount=$($r.WrittenCount)"

# ── (B) 다음 읽기: -Keep 이 처음부터 전체(5줄)를 줘도 이미 쓴 3줄은 빼고 꼬리 2줄만 ──
$r = Split-GissueJobOutTail -AllLines @('a', 'b', 'c', 'd', 'e') -WrittenCount 3
Check 'B1 꼬리 2줄만 NewLines(중복 방지)' (@($r.NewLines).Count -eq 2 -and ($r.NewLines -join ',') -eq 'd,e') "NewLines=$($r.NewLines -join ',')"
Check 'B2 카운터가 5 로' ($r.WrittenCount -eq 5) "WrittenCount=$($r.WrittenCount)"

# ── (C) 새 줄 없음: 전체와 카운터가 같으면 빈 NewLines ──
$r = Split-GissueJobOutTail -AllLines @('a', 'b', 'c') -WrittenCount 3
Check 'C1 새 줄 없으면 빈 NewLines' (@($r.NewLines).Count -eq 0) "NewLines=$($r.NewLines -join ',')"
Check 'C2 카운터 유지' ($r.WrittenCount -eq 3) "WrittenCount=$($r.WrittenCount)"

# ── (D) 전 과정 누적 중복 없음: -Keep 을 여러 번 호출하며 버퍼가 커지는 상황을 재현 ──
#   각 단계의 NewLines 를 합치면 정확히 전체 버퍼 한 벌이 되어야 한다(누락·중복 0).
$buffers = @(
    @('L1'),
    @('L1', 'L2', 'L3'),
    @('L1', 'L2', 'L3'),           # 새 줄 없이 다시 폴링
    @('L1', 'L2', 'L3', 'L4', 'L5')
)
$written = 0
$accum = New-Object System.Collections.ArrayList
foreach ($buf in $buffers) {
    $res = Split-GissueJobOutTail -AllLines $buf -WrittenCount $written
    foreach ($ln in @($res.NewLines)) { [void]$accum.Add($ln) }
    $written = $res.WrittenCount
}
Check 'D1 누적 결과가 전체 버퍼와 정확히 일치(누락·중복 0)' (($accum -join ',') -eq 'L1,L2,L3,L4,L5') "accum=$($accum -join ',')"
Check 'D2 최종 카운터 5' ($written -eq 5) "written=$written"

# ── (E) 방어: 카운터가 버퍼보다 큰 비정상(버퍼가 줄어든 경우) → 빈 NewLines + 전체 줄 수로 재동기화 ──
$r = Split-GissueJobOutTail -AllLines @('a', 'b') -WrittenCount 5
Check 'E1 카운터>전체면 빈 NewLines' (@($r.NewLines).Count -eq 0) "NewLines=$($r.NewLines -join ',')"
Check 'E2 카운터를 현재 전체(2)로 재동기화' ($r.WrittenCount -eq 2) "WrittenCount=$($r.WrittenCount)"

# ── (F) 방어: 음수 카운터는 0 으로 취급 ──
$r = Split-GissueJobOutTail -AllLines @('a', 'b') -WrittenCount -3
Check 'F1 음수 카운터는 0 취급 → 전부 NewLines' (@($r.NewLines).Count -eq 2 -and ($r.NewLines -join ',') -eq 'a,b') "NewLines=$($r.NewLines -join ',')"

# ── (G) 빈 버퍼 ──
$r = Split-GissueJobOutTail -AllLines @() -WrittenCount 0
Check 'G1 빈 버퍼면 빈 NewLines, 카운터 0' (@($r.NewLines).Count -eq 0 -and $r.WrittenCount -eq 0) "NewLines=$($r.NewLines -join ',') WrittenCount=$($r.WrittenCount)"

# ── (H) 러너 소스 배선 점검 ──
$src = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../run-gissue-claude.ps1') -Raw -Encoding UTF8
Check 'H1 lib/job-out-tail.ps1 를 소싱한다' ($src -match "lib/job-out-tail\.ps1") ''
Check 'H2 run 객체에 OutLogWritten 카운터가 있다' ($src -match 'OutLogWritten = 0') ''
Check 'H3 증분 flush 래퍼(Write-GissueJobOutIncremental)가 있다' ($src -match 'function Write-GissueJobOutIncremental') ''
Check 'H4 래퍼가 Split-GissueJobOutTail 로 꼬리를 고른다' ($src -match 'Split-GissueJobOutTail -AllLines \$all -WrittenCount') ''
Check 'H5 평상시 경로는 -Keep 으로 버퍼를 보존한다' ($src -match 'Receive-Job \$r\.Job -Keep -ErrorAction SilentlyContinue \| ForEach-Object') ''
Check 'H6 Phase 2 루프가 running 잡을 매 바퀴 증분 flush 한다' ($src -match "(?m)if \(\`$r\.Job\.State -eq 'Running'\) \{\s*\r?\n\s*try \{ \`$null = Write-GissueJobOutIncremental \`$r \}") ''
Check 'H7 Complete-Run 은 -Final 로 최종 flush+버퍼 소비한다' ($src -match '\$jobOut = Write-GissueJobOutIncremental \$r -Final') ''
# Complete-Run 이 더 이상 원시 Receive-Job 결과를 out.log 에 직접 append 하지 않는다(증분 경로로 일원화).
Check 'H8 Complete-Run 빠른 경로에 옛 직접 append(Receive-Job ... Out-File)가 없다' ($src -notmatch '\$jobOut = Receive-Job \$r\.Job;') ''

if ($fail -gt 0) { Write-Output "FAILED: $fail"; exit 1 }
Write-Output 'ALL PASS'
