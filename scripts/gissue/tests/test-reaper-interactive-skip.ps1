# test-reaper-interactive-skip.ps1 — Phase 0 reaper "대화형 세션은 죽이지 않는다" 회귀 테스트
# (giip #2960)
#
# 왜 필요한가:
#   Linux Docker 컨테이너에서 Phase 0 reaper 가 `docker exec -it <container> bash` → `claude` 로
#   사람이 띄운 대화형 세션까지 30분 뒤 강제종료했다. 원인은 run-gissue-claude.ps1 의
#   $InteractiveAncestors 조상이름 목록이 Windows 전용이라 Linux 조상 체인(sh/bash, PPID 종종 0)에는
#   절대 매치되지 않았기 때문 — 그 결과 모든 claude 프로세스가 headless 로 취급됐다.
#
# 고정하는 것:
#   Test-GissueClaudeIsHeadless — 커맨드라인에 `-p`/`--print` 토큰이 있는지로 헤드리스 여부 판정.
#     토큰 경계 매칭(원시 부분문자열 매칭 아님) — `--experimental-foo` 같은 다른 플래그 안에
#     `-p` 문자가 섞여도 오탐하지 않아야 한다.
#   Test-GissueClaudeHasInteractiveTty — `/proc/<pid>/fd/0` 심볼릭 링크 대상 문자열이
#     `/dev/pts/*`/`/dev/tty*` 면 대화형 TTY 로 판정(Linux 전용 보조 체크).
#
# 실행:
#   powershell -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-reaper-interactive-skip.ps1
# 종료코드: 0 = 전건 PASS, 1 = 1건 이상 FAIL
#
# 이 테스트는 실제 프로세스/파일시스템을 전혀 건드리지 않는다 — reaper-lib.ps1 의 순수함수만
# 문자열 입력으로 호출한다(worktree-safety.ps1 + test-worktree-idle-guard.ps1 의 A파트와 같은 패턴).

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

$ReaperLib = Join-Path $PSScriptRoot '..\reaper-lib.ps1'
$ReaperLib = (Resolve-Path -LiteralPath $ReaperLib).Path
. $ReaperLib

$script:Pass = 0
$script:Fail = 0
function Assert-True($cond, $name, $detail = '') {
    if ($cond) { $script:Pass++; Write-Output "  PASS  $name" }
    else { $script:Fail++; Write-Output "  FAIL  $name$(if ($detail) { " — $detail" })" }
}
function Assert-Null($val, $name, $detail = '') {
    Assert-True ($null -eq $val) $name $detail
}

# ──────────────────────────────────────────────────────────────────────────────
# A. Test-GissueClaudeIsHeadless
# ──────────────────────────────────────────────────────────────────────────────
Write-Output 'A. Test-GissueClaudeIsHeadless — 커맨드라인 헤드리스 판정'

# A-1 cmdline 에 '-p' 가 다른 플래그들 사이에 섞여 있음 → headless=true
$v = Test-GissueClaudeIsHeadless 'claude -p --dangerously-skip-permissions --add-dir /work --model claude-haiku-4-5'
Assert-True ($v -eq $true) 'A-1 -p 플래그(다른 플래그 사이) → headless=true' "got=$v"

# A-2 cmdline 에 '--print' → headless=true
$v = Test-GissueClaudeIsHeadless 'claude --print --allowedTools Read --add-dir /work'
Assert-True ($v -eq $true) 'A-2 --print 플래그 → headless=true' "got=$v"

# A-3 '-p'/'--print' 없음(순수 대화형 기동) → headless=false
$v = Test-GissueClaudeIsHeadless 'claude'
Assert-True ($v -eq $false) 'A-3 -p/--print 없음(bare claude) → headless=false' "got=$v"

# A-4 cmdline 이 null/빈 문자열 → headless=$null(판정불가, 호출자가 SKIP 처리해야 함)
$v = Test-GissueClaudeIsHeadless $null
Assert-Null $v 'A-4 cmdline=null → headless=$null(판정불가)' "got=$v"
$v = Test-GissueClaudeIsHeadless ''
Assert-Null $v 'A-4b cmdline=빈 문자열 → headless=$null(판정불가)' "got=$v"
$v = Test-GissueClaudeIsHeadless '   '
Assert-Null $v 'A-4c cmdline=공백만 → headless=$null(판정불가)' "got=$v"

# A-5 '-p' 가 다른 단어 안에 부분문자열로만 섞임(토큰 경계 미충족) → false-positive 금지
$v = Test-GissueClaudeIsHeadless 'claude --experimental-foo --add-dir /opt/app-path'
Assert-True ($v -eq $false) 'A-5 --experimental-foo(부분문자열 -p 오탐 금지) → headless=false' "got=$v"

# A-6 대화형 세션이 마침 -p 로 시작하는 경로를 인자로 받은 경우도 토큰 전체 일치가 아니므로 오탐 금지
$v = Test-GissueClaudeIsHeadless 'claude --add-dir /path/to/-project'
Assert-True ($v -eq $false) 'A-6 경로 안 "-p" 부분문자열(토큰 아님) → headless=false' "got=$v"

# A-7 '-p' 가 맨 앞/맨 끝 토큰이어도 정상 인식(경계 조건)
$v = Test-GissueClaudeIsHeadless '-p'
Assert-True ($v -eq $true) 'A-7 cmdline 전체가 -p 하나뿐 → headless=true' "got=$v"

# ──────────────────────────────────────────────────────────────────────────────
# B. Test-GissueClaudeHasInteractiveTty
# ──────────────────────────────────────────────────────────────────────────────
Write-Output ''
Write-Output 'B. Test-GissueClaudeHasInteractiveTty — TTY 보조 판정(Linux 전용 체크)'

$v = Test-GissueClaudeHasInteractiveTty '/dev/pts/3'
Assert-True ($v -eq $true) 'B-1 /dev/pts/3 → interactive=true' "got=$v"

$v = Test-GissueClaudeHasInteractiveTty '/dev/tty1'
Assert-True ($v -eq $true) 'B-2 /dev/tty1 → interactive=true' "got=$v"

$v = Test-GissueClaudeHasInteractiveTty '/dev/null'
Assert-True ($v -eq $false) 'B-3 /dev/null → interactive=false' "got=$v"

$v = Test-GissueClaudeHasInteractiveTty ''
Assert-True ($v -eq $false) 'B-4 빈 문자열 → interactive=false' "got=$v"

$v = Test-GissueClaudeHasInteractiveTty $null
Assert-True ($v -eq $false) 'B-5 $null → interactive=false' "got=$v"

$v = Test-GissueClaudeHasInteractiveTty 'pipe:[12345]'
Assert-True ($v -eq $false) 'B-6 파이프 fd → interactive=false' "got=$v"

Write-Output ''
Write-Output "결과: PASS=$($script:Pass) FAIL=$($script:Fail)"
if ($script:Fail -gt 0) { exit 1 }
exit 0
