# gissue-stash-unblock-lib.ps1 — auto-unblock 의 stash 단계 정본 로직 (예약장치명 부분 성공 + untracked 잔해 폴백)
#
# 이 파일이 정본인 이유:
#   auto-unblock 의 stash 단계는 run-gissue-claude.ps1 안의 **두 호출부**(병합 확인된 [AUTO-UNBLOCK] 경로와
#   병합 미확인 [AUTO-UNBLOCK-FORCED] 경로)에서 쓰인다. 판정·폴백 로직을 두 곳에 복붙하면 한쪽만 고쳐져
#   다른 쪽이 조용히 구 동작으로 남는다 — 안전로직 복붙본 중 하나만 수정돼 다른 경로가 의도와 다르게
#   동작하는 사고는 이미 이 계열에서 한 번 발생했다. 그래서 판정·실행 로직을 **여기 한 벌**로 모은다.
#   run-gissue-claude.ps1 은 최상위 스크립트라 닷소싱만으로는 테스트할 수 없다(소싱하면 스케줄러 전체가
#   돈다). 그래서 이 lib 를 별도 파일로 둔다 — 러너와 회귀 테스트가 **같은 코드를** 공유한다.
#
# ── 결함 A: Windows 예약장치명 untracked 파일 때문에 `git stash push -u` 가 부분 성공한다 ────────────
#
#   재현(임시 git 저장소에서 실측):
#     tracked 파일 1개를 수정하고, untracked 로 예약장치명 파일(`nul` 등) 1개 + 일반 파일 1개를 만든 뒤
#     `git stash push -u -m ...` 를 실행하면:
#       · 종료코드 = 1
#       · 출력:
#           Ignoring path nul
#           Saved working directory and index state On master: ...
#           warning: failed to remove nul: Permission denied
#       · **stash 엔트리는 실제로 생성된다**(tracked 변경이 stash 안에 보존된다)
#       · **작업 트리는 리셋되지 않는다**(수정된 tracked 파일과 예약장치명 파일이 그대로 남는다)
#
#   즉 이 출력은 "stash 실패"가 아니라 **부분 성공(보존 성공)** 이다. 그런데 exit != 0 만 보고 실패로
#   판정하면 base 복귀를 포기하게 되고, 그 탓에:
#     · base 로 복귀하지 못해 auto-unblock 이 무한 반복된다
#     · 매 회차마다 stash 가 하나씩 더 쌓인다(워킹트리가 리셋되지 않아 다음 회차에도 stash 대상이 남음)
#
#   **결함을 막는 것은 stash 판정이다** — `git checkout <base>` 는 이런 잔여 파일이 있어도 성공한다
#   (실측: 종료코드 0). 즉 untracked 잔류는 base 복귀를 막지 않는다.
#
#   대응(여기서 하는 일):
#     · 위 시그니처(부분 성공)를 순수 판정 함수로 식별한다 → "보존 성공"으로 분류
#     · **tracked 전용 stash(`git stash push`, `-u` 없음)로 1회 폴백**한다 → 워킹트리의 tracked 변경이
#       실제로 리셋되고, **종료코드 0** 으로 base 복귀가 계속 진행된다
#     · 예약장치명 파일은 **지우거나 이동하지 않는다**(워킹트리에 그대로 둔다 — 파괴적 작업 금지).
#       사람이 직접 제거해야 하므로 그 사실을 사람이 볼 수 있는 로그 1줄로 남긴다.
#
# ── 결함 B: untracked 잔해(경로 길이 초과 계열)로 `git stash push -u` 가 실패한다 ───────────────────
#
#   `git stash push -u` 는 untracked 를 전부 보존하려다, 레포에 남은 깊은 트리에서 Windows 경로길이
#   한계로 죽는다(`Cannot save the untracked files` / `Filename too long` / `Unable to process path`).
#   base 복귀에 untracked 보존은 필요 없으므로 tracked 전용 stash 로 1회 재시도한다.
#   (이 계열은 정본 문서 §10 에 선례가 이미 기록돼 있다 — "Filename too long" 류.)
#
# 반환 계약(중요 — 호출부는 .Ok / .ErrDetail / .LogLines 만 읽는다):
#   Ok = $true 는 **exit 0 을 함의**한다. 부분 성공 경로에서도 폴백 stash 가 exit 0 이므로 Ok=$true,
#   ExitCode=0 으로 돌려준다. Ok=$false 면 ErrDetail 에 사유가 들어 있다.

# ──────────────────────────────────────────────────────────────────────────────
# 순수 판정 — 부수효과 없음, 테스트가 직접 호출한다
# ──────────────────────────────────────────────────────────────────────────────

# Windows 예약장치명(예약 이름) 집합. 이 이름들은 확장자를 붙여도(`nul.txt`) 장치로 해석된다.
$script:GissueWindowsReservedDeviceNames = @(
    'CON', 'PRN', 'AUX', 'NUL',
    'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
    'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
    'CLOCK$'
)

# 파일명(경로의 마지막 요소)이 Windows 예약장치명인지 판정한다.
# 경로가 들어와도 마지막 요소만 본다 — `sub/nul` 도 예약장치명이다.
function Test-GissueWindowsReservedDeviceName($name) {
    if (-not $name) { return $false }
    $leaf = (Split-Path -Leaf ([string]$name))
    $leaf = $leaf.Trim().Trim('"')
    if (-not $leaf) { return $false }
    # 확장자를 떼어 내고 대문자로 비교한다 — `nul.txt` 도 Windows 는 장치로 해석한다.
    $base = [System.IO.Path]::GetFileNameWithoutExtension($leaf)
    if (-not $base) { $base = $leaf }
    return (@($script:GissueWindowsReservedDeviceNames) -contains $base.ToUpperInvariant())
}

# stash 출력에서 "untracked 정리가 실패했다"는 시그니처가 나오는 파일 이름을 뽑는다.
#   · `Ignoring path <name>`
#   · `warning: failed to remove <name>: Permission denied`
# 경로에 공백/따옴표가 있을 수 있어 git 은 따옴표로 감싸 출력한다 — 따옴표는 벗겨서 돌려준다.
function Get-GissueStashRemovalFailurePaths($stashOutText) {
    $paths = @()
    if (-not $stashOutText) { return $paths }
    $lines = (($stashOutText | ForEach-Object { $_.ToString() }) -join "`n") -split "`n"
    foreach ($line in $lines) {
        $raw = $line -replace "`r", ''
        $m = [regex]::Match($raw, '(?i)Ignoring path\s+(?<name>.+?)\s*$')
        if (-not $m.Success) {
            $m = [regex]::Match($raw, '(?i)failed to remove\s+(?<name>.+?):\s*Permission denied')
        }
        if ($m.Success) {
            $p = $m.Groups['name'].Value.Trim().Trim('"')
            if ($p) { $paths += $p }
        }
    }
    return @($paths | Select-Object -Unique)
}

# stash 출력에서 **Windows 예약장치명**으로 남은 파일 이름만 뽑아 배열로 반환한다.
# 일반 파일(예: 다른 프로세스가 잠근 파일)로 인한 "failed to remove" 는 여기 포함되지 않는다 —
# 예약장치명 판정의 근거로만 쓴다(아래 Test-GissueStashReservedNameFailure 참고).
function Get-GissueStashReservedNamePaths($stashOutText) {
    $paths = @()
    foreach ($p in @(Get-GissueStashRemovalFailurePaths $stashOutText)) {
        if (Test-GissueWindowsReservedDeviceName $p) { $paths += $p }
    }
    return @($paths | Select-Object -Unique)
}

# `git stash push -u` 가 "부분 성공(보존 성공)" 으로 끝났는지 판정한다.
#
# 판정 조건(둘 다 만족해야 한다):
#   (1) 출력에 stash 저장 성공 표시가 있다 — `Saved working directory and index state`
#       (이게 없으면 stash 자체가 안 만들어진 진짜 실패다)
#   (2) untracked 정리 실패 시그니처가 있다 — `failed to remove <이름>: Permission denied`
#       또는 `Ignoring path <이름>` — 그리고 그 이름이 Windows 예약장치명이다.
#
# 왜 예약장치명 조건까지 거는가:
#   예약장치명 이외의 파일이 "failed to remove" 이 된 것은(다른 프로세스가 잠췄다든지) 원인이 다르고
#   대응도 다르다. 특히 "부분 성공" 으로 분류하면 워킹트리가 리셋되지 않은 상태로 base 복귀를 진행하게
#   되므로, 예약장치명처럼 **재현 가능하고 남은 채로 두어도 checkout 을 막지 않는** 경우로 한정한다.
#
# 경로 길이 초과 계열(`Cannot save the untracked files` / `Filename too long` /
# `Unable to process path`)은 **별개**로 판정한다(Test-GissueStashUntrackedFailure) — 원인이 다르고
# 대응도 다르다(부분 성공이 아니라 stash 자체 실패 → tracked 전용 재시도로 처리).
function Test-GissueStashReservedNameFailure($stashOutText) {
    if (-not $stashOutText) { return $false }
    $joined = ($stashOutText | Out-String)
    if ($joined -notmatch '(?i)Saved working directory and index state') { return $false }
    $reserved = @(Get-GissueStashReservedNamePaths $stashOutText)
    return (@($reserved).Count -gt 0)
}

# `git stash push -u` 의 실패가 "untracked 잔해(경로 길이 초과 계열)" 때문인지 판정한다.
# true 면 `-u` 를 뺀 tracked 전용 stash 로 재시도할 가치가 있다.
function Test-GissueStashUntrackedFailure($stashOutText) {
    if (-not $stashOutText) { return $false }
    $joined = ($stashOutText | Out-String)
    if ($joined -match '(?i)Cannot save the untracked files') { return $true }
    if ($joined -match '(?i)Filename too long') { return $true }
    if ($joined -match '(?i)Unable to process path') { return $true }
    return $false
}

# ──────────────────────────────────────────────────────────────────────────────
# 실행 경로 — git 을 실제로 부른다
# ──────────────────────────────────────────────────────────────────────────────

# auto-unblock 의 stash 단계.
#   1) `git stash push -u` 로 먼저 시도한다(untracked 보존).
#   2) 실패(exit != 0) 하면 **원인을 분류**한다:
#      · 예약장치명 부분 성공(보존 성공) → tracked 전용 stash 로 폴백해 워킹트리를 리셋한다
#      · untracked 잔해(경로 길이 초과 계열) → tracked 전용 stash 로 폴백한다
#      · 그 외 → 기존 실패 경로(포기) 그대로. **진짜 실패의 기존 동작은 바꾸지 않는다.**
#   3) 폴백 stash 가 exit 0 이면 Ok=$true/ExitCode=0 으로 돌려줘 호출부가 base 복귀를 계속 진행한다.
#
# 반환 오브젝트: Ok / ExitCode / UsedUntracked / ErrDetail / LogLines / Output / ReservedNames
#   LogLines 은 호출자가 그대로 Write-Output 해야 한다(조용한 동작 변경 금지 — 무엇이 왜 일어났는지
#   반드시 로그에 남긴다).
function Invoke-GissueAutoUnblockStash($repo, $stashMsg) {
    # PowerShell 5.1 함정 회피: 호출 스코프의 $ErrorActionPreference 가 'Stop' 이면 git 이 stderr 로
    # 한 줄만 내보내도 NativeCommandError 가 terminating 이 되어 폴백 분기에 도달하기 전에 죽는다.
    # 여기서만 낮춘다(나오면 자동 복원된다).
    $ErrorActionPreference = 'Continue'
    $logLines = @()
    try {
        $out = & git -C $repo stash push -u -m $stashMsg 2>&1
        $exit = $LASTEXITCODE
        if ($exit -eq 0) {
            return [pscustomobject]@{
                Ok = $true; ExitCode = 0; UsedUntracked = $true
                ErrDetail = ''; LogLines = @(); Output = $out; ReservedNames = @()
            }
        }
        $joined = (($out | ForEach-Object { $_.ToString() }) -join ' / ')
        $reserved = @(Get-GissueStashReservedNamePaths $out)
        $isReservedPartial = Test-GissueStashReservedNameFailure $out
        $isUntrackedResidue = Test-GissueStashUntrackedFailure $out

        if (-not ($isReservedPartial -or $isUntrackedResidue)) {
            # 원인 분류에 걸리지 않는 실패 — 기존 포기 경로로 그대로 보낸다(기존 동작 유지).
            return [pscustomobject]@{
                Ok = $false; ExitCode = $exit; UsedUntracked = $true
                ErrDetail = "stash push 실패(exit=$exit): $joined"
                LogLines = @(); Output = $out; ReservedNames = $reserved
            }
        }

        if ($isReservedPartial) {
            # 부분 성공(보존 성공): stash 는 만들어졌고 tracked 변경도 stash 안에 보존돼 있다.
            # 문제는 워킹트리가 리셋되지 않았다는 것뿐이다 → tracked 전용 stash 로 폴백해 리셋한다.
            $names = ($reserved -join ', ')
            $logLines += "[AUTO-UNBLOCK] stash 는 성공했으나 untracked 정리만 실패(Windows 예약장치명 잔류: $names) — base 복귀를 계속 진행한다."
            $logLines += "[AUTO-UNBLOCK] 예약장치명 파일은 워킹트리에 그대로 둔다(파괴적 제거 금지) — 수동 제거 필요: cmd /c del \\.\$names"
            $logLines += "[AUTO-UNBLOCK] stash -u 원본 출력(exit=$exit): $joined"
        } else {
            $logLines += "[AUTO-UNBLOCK] stash -u 실패(untracked 잔해) → tracked 전용 stash 로 재시도: $repo"
            $logLines += "[AUTO-UNBLOCK] stash -u 원본 실패(exit=$exit): $joined"
        }

        # 폴백: tracked 전용 stash. untracked 를 건드리지 않으므로 예약장치명 때문에 죽지 않는다.
        $out2 = & git -C $repo stash push -m $stashMsg 2>&1
        $exit2 = $LASTEXITCODE
        if ($exit2 -ne 0) {
            $joined2 = (($out2 | ForEach-Object { $_.ToString() }) -join ' / ')
            return [pscustomobject]@{
                Ok = $false; ExitCode = $exit2; UsedUntracked = $false
                ErrDetail = "stash push 실패(exit=$exit): $joined — tracked 전용 재시도도 실패(exit=$exit2): $joined2"
                LogLines = $logLines; Output = $out2; ReservedNames = $reserved
            }
        }
        # ⚠ 예약장치명 잔류는 checkout 을 막지 않는다(실측: `git checkout <base>` 종료코드 0).
        #   잔류 파일은 지우지 않는다 — 워킹트리에 그대로 둔다.
        $logLines += "[AUTO-UNBLOCK] '-u' 를 생략한 tracked 전용 stash 로 보존 성공 — 워킹트리의 tracked 변경이 리셋되었다. untracked 잔류(예약장치명 등)는 워킹트리에 그대로 남으며 base checkout 을 막지 않는다."
        return [pscustomobject]@{
            Ok = $true; ExitCode = 0; UsedUntracked = $false
            ErrDetail = ''; LogLines = $logLines; Output = $out2; ReservedNames = $reserved
        }
    } catch {
        return [pscustomobject]@{
            Ok = $false; ExitCode = 1; UsedUntracked = $true
            ErrDetail = "stash push 예외: $($_.Exception.Message)"
            LogLines = $logLines; Output = @(); ReservedNames = @()
        }
    }
}
