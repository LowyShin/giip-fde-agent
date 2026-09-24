# reaper-lib.ps1 — Phase 0 reaper(스테일 headless claude 프로세스 회수) 판정 공용 함수 모듈
# (dot-source 전용, giip #2960)
#
# 왜 별도 파일인가:
#   `run-gissue-claude.ps1` 은 최상위 스케줄러 스크립트라 전체를 dot-source 해 단위테스트할 수
#   없다(실행하면 스케줄러 전체가 돈다). `worktree-safety.ps1` + `tests/test-worktree-idle-guard.ps1`
#   이 이미 쓰는 패턴 — "판정 로직만 순수함수로 별도 파일에 빼서 그 파일만 dot-source 테스트한다" —
#   을 그대로 따른다.
#
# 배경(giip #2960 실측, Linux Docker 컨테이너 `giip-fde-agent` 이미지):
#   Phase 0 reaper 는 "이전 실행이 남긴 스테일/고아 headless claude 프로세스"만 30분 기준으로
#   종료해야 하는데, 실제로는 사람이 `docker exec -it <container> bash` → `claude` 로 띄운
#   **대화형** 세션까지 30분 뒤 작업 중간에 강제종료했다.
#
#   원인: run-gissue-claude.ps1 의 $InteractiveAncestors 가
#     @('WindowsTerminal.exe','explorer.exe','Code.exe','devenv.exe')
#   처럼 Windows 전용 프로세스 이름만 나열한다. `docker exec` 로 띄운 대화형 세션의 조상 체인은
#   보통 sh/bash 이고 컨테이너 안에서는 PPID 가 0 인 경우가 많아, 이 조상 이름 목록에 절대
#   걸리지 않는다 — 그 결과 Linux 에서는 "대화형이라 SKIP" 판정이 한 번도 발동하지 않고 모든
#   claude 프로세스가 headless 로 취급됐다.
#
#   이 파일이 추가하는 것은 OS 조상이름에 의존하지 않는 "헤드리스 여부" 판정
#   (Test-GissueClaudeIsHeadless, 커맨드라인에 `-p`/`--print` 유무로 판정) 과, Linux 전용
#   보조판정인 TTY 체크(Test-GissueClaudeHasInteractiveTty)다. 기존 $InteractiveAncestors 조상
#   판정은 그대로 유지되고(Windows 회귀 방지), 이 파일의 판정은 그 위에 OR 로 추가된다.
#
# 이 파일은 함수 정의만 한다 — 실행 시 부작용(프로세스 종료·`/proc` 읽기 등)이 전혀 없다.
# `/proc` 읽기·`Get-Item -Path "/proc/$pid/fd/0"` 같은 실제 조회는 전부 호출자
# (run-gissue-claude.ps1 의 Phase 0 블록)가 하고, 그 결과 문자열만 이 함수들에 넘긴다.

# ---------------------------------------------------------------------------
# claude 프로세스의 커맨드라인으로 "헤드리스(스케줄러가 띄운 `-p`/`--print` 1회성 호출)인가"를
# 판정한다.
#
# 반환값:
#   $true  — 커맨드라인에 `-p` 또는 `--print` 토큰이 있음(헤드리스, reaper 종료 후보).
#   $false — 커맨드라인은 읽었으나 `-p`/`--print` 토큰이 없음(대화형으로 간주, SKIP).
#   $null  — 커맨드라인을 판정할 수 없음(비어있음/null). 호출자는 이를 "판정불가 → fail-safe로
#            SKIP(죽이지 않음)"으로 취급해야 한다.
#
# 토큰 경계 판정(정규식/분할 기반, 원시 부분문자열 매칭 아님)을 쓰는 이유: `-like '*-p*'` 같은
# 부분문자열 매칭은 `--experimental-foo` 나 경로에 `-p` 가 섞인 인자(`/opt/app`)를 오탐으로
# `-p` 플래그로 잘못 판정한다. 공백으로 토큰을 나눈 뒤 토큰 전체가 정확히 `-p`/`--print` 인
# 경우만 인정한다.
function Test-GissueClaudeIsHeadless {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$CommandLine
    )
    if ([string]::IsNullOrWhiteSpace($CommandLine)) { return $null }

    $tokens = @($CommandLine -split '\s+' | Where-Object { $_ -ne '' })
    foreach ($t in $tokens) {
        if ($t -eq '-p' -or $t -eq '--print') { return $true }
    }
    return $false
}

# ---------------------------------------------------------------------------
# `/proc/<pid>/fd/0`(표준입력) 심볼릭 링크 대상 문자열을 받아, 그게 대화형 터미널(TTY)인지
# 순수 문자열 매칭으로 판정한다(Linux 전용 보조 체크). 실제 `/proc` 읽기/`Get-Item` 호출은
# 호출자가 하고, 여기서는 이미 읽은 대상 문자열(예: '/dev/pts/3', '/dev/tty1', '/dev/null')만
# 받는다 — 그래야 실제 파일시스템을 건드리지 않고도 테스트할 수 있다.
#
# 반환값: `$true`(대화형 TTY) / `$false`(TTY 아님 — /dev/null, 파이프, 빈 값 등).
function Test-GissueClaudeHasInteractiveTty {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [AllowEmptyString()]
        [string]$Fd0Target
    )
    if ([string]::IsNullOrWhiteSpace($Fd0Target)) { return $false }
    if ($Fd0Target -like '/dev/pts/*') { return $true }
    if ($Fd0Target -like '/dev/tty*') { return $true }
    return $false
}
