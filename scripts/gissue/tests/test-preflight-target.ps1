# [giip 4804] 프리플라이트(LLM 기동 전 "대상 0건" 판정) 단위 테스트
# 실행: pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-preflight-target.ps1
# 네트워크 쓰기/파일 쓰기 없음. lib/preflight-target.ps1 의 판정 함수를 가짜 포트로 전 경로 검증하고,
# 러너 소스에서 "게이트가 REPO-MAINT Start-Job 보다 앞"인지, lib 가 읽기 전용인지까지 확인한다.
$ErrorActionPreference = 'Stop'
. (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../lib/preflight-target.ps1')).Path

$fail = 0
function Check($name, $ok, $detail) {
    $b = $false
    if ($ok -is [bool]) { $b = $ok } elseif ($null -ne $ok) { $b = [bool]$ok }
    if ($b) { Write-Output "[PASS] $name" } else { $script:fail++; Write-Output "[FAIL] $name - $detail" }
}
function HasWarn($decision) { return (@(@($decision.LogLines) | Where-Object { $_ -match '\[PREFLIGHT\]\[WARN\]' }).Count -ge 1) }
function SkipLines($decision) { return @(@($decision.LogLines) | Where-Object { $_ -match '^SKIP ' }) }
# 가짜 포트 — 전부 P-6 결과 오브젝트를 돌려준다. $null 을 주면 "판정 불능" 포트.
function PortsOf($conf, $ci, $stash, $recent) {
    return @{
        ListConflictingPrs      = { param($r) if ($null -eq $conf)   { New-GissuePreflightUnknown 'fake-conf' }   else { New-GissuePreflightCount $conf } }.GetNewClosure()
        ListFailingCiPrs        = { param($r) if ($null -eq $ci)     { New-GissuePreflightUnknown 'fake-ci' }     else { New-GissuePreflightCount $ci } }.GetNewClosure()
        ListAutoUnblockStash    = { param($r) if ($null -eq $stash)  { New-GissuePreflightUnknown 'fake-stash' }  else { New-GissuePreflightCount $stash } }.GetNewClosure()
        ListRecentCommentIssues = {           if ($null -eq $recent) { New-GissuePreflightUnknown 'fake-recent' } else { New-GissuePreflightCount $recent } }.GetNewClosure()
    }
}
$R1 = @('/tmp/repoA')
$R2 = @('/tmp/repoA', '/tmp/repoB')

# ── (a) 전부 확정 0건 -> 기동하지 않는다 ────────────────────────────────────────
$m = Measure-GissueRepoMaintTargets $R1 (PortsOf 0 0 0 0)
Check 'a1 전부 0건이면 Total=0'               ($m.Total -eq 0) "Total=$($m.Total)"
Check 'a2 전부 확정이면 Unknown=false'         (-not $m.Unknown) "reasons=$(@($m.UnknownReasons) -join '|')"
Check 'a3 포트 4본이 확정값을 돌려줬다'         ($m.PortsResolved -eq 4) "resolved=$($m.PortsResolved)"
$d = Test-GissuePreflightShouldSpawn $m 'REPO-MAINT'
Check 'a4 0건이면 Spawn=false'                (-not $d.Spawn) "reason=$($d.Reason)"
Check 'a5 reason=no-target'                   ($d.Reason -eq 'no-target') "reason=$($d.Reason)"
# P-3: 로그 행은 자유서식이 아니라 계약이다(수락조건이 이 행을 로그로 제시하라고 요구).
$sl = @(SkipLines $d)
Check 'a6 SKIP 행이 정확히 1건'                ($sl.Count -eq 1) "lines=$(@($d.LogLines) -join ' // ')"
Check 'a7 SKIP 행이 계약과 글자 그대로 일치'    ("$($sl[0])" -eq 'SKIP reason=no-target job=REPO-MAINT count=0') "실제='$($sl[0])'"
Check 'a8 job 이름이 인자로 바뀐다'             ((@(SkipLines (Test-GissuePreflightShouldSpawn $m 'ISSUE-SWEEP')))[0] -eq 'SKIP reason=no-target job=ISSUE-SWEEP count=0') ''
Check 'a9 0건일 때 WARN 은 내지 않는다'         (-not (HasWarn $d)) "lines=$(@($d.LogLines) -join ' // ')"
# 「측정했는데 0」과 「측정 안 함」을 로그에서 구별할 수 있어야 한다 — 0건이어도 내역 행은 남는다.
Check 'a10 0건이어도 내역(conflict/ci-fail/stash/recent-comment)이 로그에 남는다' `
    ((@($d.LogLines) -join ' ') -match 'conflict=0.*ci-fail=0.*stash=0.*recent-comment=0') "lines=$(@($d.LogLines) -join ' // ')"
Check 'a11 내역에 레포 수가 들어간다'            ((@($m.Detail) -join ' ') -match 'repos=1') "detail=$(@($m.Detail) -join ' ')"

# ── (b) 대상이 1건이라도 있으면 기동한다 ───────────────────────────────────────
foreach ($case in @(
    @{ N = 'b1 [0] conflict 1건';  P = (PortsOf 1 0 0 0); Field = 'Conflicting' },
    @{ N = 'b2 [E] CI 실패 1건';    P = (PortsOf 0 1 0 0); Field = 'FailingCi' },
    @{ N = 'b3 [F] stash 1건';      P = (PortsOf 0 0 1 0); Field = 'OrphanStash' },
    @{ N = 'b4 [H] 최근코멘트 1건'; P = (PortsOf 0 0 0 1); Field = 'RecentComment' }
)) {
    $mm = Measure-GissueRepoMaintTargets $R1 $case.P
    $dd = Test-GissuePreflightShouldSpawn $mm 'REPO-MAINT'
    Check "$($case.N) -> Total=1 / Spawn / has-target" (($mm.Total -eq 1) -and ($mm."$($case.Field)" -eq 1) -and $dd.Spawn -and ($dd.Reason -eq 'has-target')) "Total=$($mm.Total) field=$($mm."$($case.Field)") reason=$($dd.Reason)"
    Check "$($case.N) -> SKIP 행을 내지 않는다"        ((@(SkipLines $dd)).Count -eq 0) "lines=$(@($dd.LogLines) -join ' // ')"
}

# ── (c) 레포가 여러 개면 레포별로 합산한다 ──────────────────────────────────────
$m = Measure-GissueRepoMaintTargets $R2 (PortsOf 1 0 2 0)
Check 'c1 conflict 가 레포 수만큼 합산'    ($m.Conflicting -eq 2) "Conflicting=$($m.Conflicting)"
Check 'c2 stash 가 레포수 x 건수로 합산'   ($m.OrphanStash -eq 4) "OrphanStash=$($m.OrphanStash)"
Check 'c3 [H] 는 CSN 단위라 1회만 센다'    ($m.RecentComment -eq 0) "RecentComment=$($m.RecentComment)"
Check 'c4 Total = 2+0+4+0'                 ($m.Total -eq 6) "Total=$($m.Total)"
Check 'c5 PortsResolved = 레포2 x 3 + 1'   ($m.PortsResolved -eq 7) "resolved=$($m.PortsResolved)"

# ── (d) 판정 불능은 0건으로 읽지 않는다(P-1/P-2) ────────────────────────────────
$m = Measure-GissueRepoMaintTargets $R1 (PortsOf $null 0 0 0)
Check 'd1 판정불능 포트 1본이면 Unknown=true'  ($m.Unknown) ''
Check 'd2 그래도 Total 은 0'                   ($m.Total -eq 0) "Total=$($m.Total)"
Check 'd3 사유가 기록된다'                     ((@($m.UnknownReasons) -join '|') -match 'fake-conf') "reasons=$(@($m.UnknownReasons) -join '|')"
$d = Test-GissuePreflightShouldSpawn $m 'REPO-MAINT'
Check 'd4 0건처럼 보여도 Spawn=true'           ($d.Spawn) "reason=$($d.Reason)"
Check 'd5 reason=preflight-unknown'            ($d.Reason -eq 'preflight-unknown') "reason=$($d.Reason)"
Check 'd6 조용히 skip 하지 않고 WARN 을 낸다'   (HasWarn $d) "lines=$(@($d.LogLines) -join ' // ')"
Check 'd7 SKIP 행은 내지 않는다'                ((@(SkipLines $d)).Count -eq 0) "lines=$(@($d.LogLines) -join ' // ')"

# 포트가 예외를 던져도 같다(0건 아님)
$m = Measure-GissueRepoMaintTargets $R1 @{
    ListConflictingPrs      = { param($r) throw 'gh 401 Bad credentials' }
    ListFailingCiPrs        = { param($r) New-GissuePreflightCount 0 }
    ListAutoUnblockStash    = { param($r) New-GissuePreflightCount 0 }
    ListRecentCommentIssues = {           New-GissuePreflightCount 0 }
}
Check 'd8 포트 예외도 Unknown'                 ($m.Unknown) ''
Check 'd9 예외 사유가 기록된다'                ((@($m.UnknownReasons) -join '|') -match 'Bad credentials') "reasons=$(@($m.UnknownReasons) -join '|')"
Check 'd10 예외가 있으면 Spawn=true'           ((Test-GissuePreflightShouldSpawn $m 'REPO-MAINT').Spawn) ''

# P-6 핵심: 포트가 "그냥 빈 배열"을 돌려주면 0건이 아니라 계약 위반(Unknown)으로 다룬다.
#   PowerShell 은 scriptblock 이 반환한 @() 를 $null 로 접어버리므로, 빈 배열을 "확정 0건"으로
#   읽는 설계는 "gh 가 401 로 죽었다"와 구별이 **원리적으로 불가능**하다. 그 혼동이 그대로
#   "gh 가 죽어 있는 동안 영원히 LLM 미기동"이 되므로, 여기서 반드시 Unknown 으로 떨어뜨린다.
$m = Measure-GissueRepoMaintTargets $R1 @{
    ListConflictingPrs      = { param($r) @() }
    ListFailingCiPrs        = { param($r) @() }
    ListAutoUnblockStash    = { param($r) @() }
    ListRecentCommentIssues = {           @() }
}
Check 'd11 생배열(빈) 반환은 Unknown'          ($m.Unknown) ''
Check 'd12 그 사유에 "契約違反" 이 들어간다'   ((@($m.UnknownReasons) -join '|') -match '契約違反') "reasons=$(@($m.UnknownReasons) -join '|')"
Check 'd13 생배열이면 SKIP 하지 않는다'        ((@(SkipLines (Test-GissuePreflightShouldSpawn $m 'REPO-MAINT'))).Count -eq 0) ''
$m = Measure-GissueRepoMaintTargets $R1 @{
    ListConflictingPrs      = { param($r) @('pr1','pr2') }
    ListFailingCiPrs        = { param($r) New-GissuePreflightCount 0 }
    ListAutoUnblockStash    = { param($r) New-GissuePreflightCount 0 }
    ListRecentCommentIssues = {           New-GissuePreflightCount 0 }
}
Check 'd14 생배열(2건)도 Count 로 세지 않는다' ($m.Conflicting -eq 0) "Conflicting=$($m.Conflicting)"
Check 'd15 생배열(2건)은 Unknown 으로 기동'    ((Test-GissuePreflightShouldSpawn $m 'REPO-MAINT').Reason -eq 'preflight-unknown') ''

# ── (e) P-4 측정자 전멸은 0건이 아니다 ──────────────────────────────────────────
$m = Measure-GissueRepoMaintTargets @() @{}
Check 'e1 레포 0개 + 포트 없음 -> PortsResolved=0' ($m.PortsResolved -eq 0) "resolved=$($m.PortsResolved)"
Check 'e2 그 경우 Unknown=true(0건으로 읽지 않음)' ($m.Unknown) ''
Check 'e3 Spawn=true'                              ((Test-GissuePreflightShouldSpawn $m 'REPO-MAINT').Spawn) ''
Check 'e4 전멸 사유가 기록된다'                    ((@($m.UnknownReasons) -join '|') -match '1本も確定値') "reasons=$(@($m.UnknownReasons) -join '|')"
$d = Test-GissuePreflightShouldSpawn $null 'REPO-MAINT'
Check 'e5 판정 결과 자체가 null 이어도 Spawn=true' ($d.Spawn -and ($d.Reason -eq 'preflight-unknown')) "reason=$($d.Reason)"
Check 'e6 그때도 WARN 을 낸다'                     (HasWarn $d) ''
# 레포가 0개여도 [H] 포트만 확정이면, 그 1본은 센다 — 다만 Unknown 은 아니다.
$m = Measure-GissueRepoMaintTargets @() @{ ListRecentCommentIssues = { New-GissuePreflightCount 0 } }
Check 'e7 레포0개+[H]확정0 -> Unknown=false'       (-not $m.Unknown) "reasons=$(@($m.UnknownReasons) -join '|')"
Check 'e8 그 경우 Spawn=false(SKIP)'               (-not (Test-GissuePreflightShouldSpawn $m 'REPO-MAINT').Spawn) ''

# ── (f) 대상이 있는데 일부 판정 불능이면: 기동하고 WARN 도 같이 낸다 ───────────
$m = Measure-GissueRepoMaintTargets $R1 (PortsOf 1 $null 0 0)
$d = Test-GissuePreflightShouldSpawn $m 'REPO-MAINT'
Check 'f1 has-target 이면서'  ($d.Reason -eq 'has-target') "reason=$($d.Reason)"
Check 'f2 WARN 도 함께 낸다'  (HasWarn $d) "lines=$(@($d.LogLines) -join ' // ')"

# ── (g) 실포트: 실패는 Ok=false, 성공은 Count 로 구분된다 ──────────────────────
$bad = Get-GissuePreflightAutoUnblockStash '/nonexistent/path/giip4804'
Check 'g1 없는 경로의 stash 조회는 Ok=false'      (-not $bad.Ok) "ret=$($bad | Out-String)"
Check 'g2 그 반환도 결과 오브젝트 형태다'          (Test-GissuePreflightResultShape $bad) ''
$badPr = Get-GissuePreflightOpenPrJson '/nonexistent/path/giip4804'
Check 'g3 없는 경로의 PR 조회는 Ok=false'          (-not $badPr.Ok) ''
$badLi = Get-GissuePreflightRecentCommentIssues '/nonexistent/list-issues.js' 70418 '/x' 'https://x'
Check 'g4 없는 list-issues.js 는 Ok=false'         (-not $badLi.Ok) ''
$selfRepo = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../../..')).Path
$stashRes = Get-GissuePreflightAutoUnblockStash $selfRepo
Check 'g5 실제 레포의 stash 조회는 Ok=true(확정)'  ($stashRes.Ok) "repo=$selfRepo err=$($stashRes.Error)"
Check 'g6 그 Count 는 0 이상 정수'                 ($stashRes.Count -ge 0) "count=$($stashRes.Count)"
$prim = Select-GissuePreflightPrimaryRepos @($selfRepo, $selfRepo, '/nonexistent/path/giip4804')
Check 'g7 같은 레포 중복은 1개로 접힌다'           (@($prim).Count -eq 1) "prim=$(@($prim) -join ',')"
Check 'g8 git 레포가 아닌 경로는 빠진다'           (-not (@($prim) -contains '/nonexistent/path/giip4804')) "prim=$(@($prim) -join ',')"

# ── (h) 러너 배선: 게이트가 REPO-MAINT Start-Job 보다 앞에 있어야 한다 ─────────
$src = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../run-gissue-claude.ps1') -Raw -Encoding UTF8

# [giip 4806] ⚠ 同じ判定文が **DryRun 分岐にも在る**（giip 4806 が `-DryRun` にも実運転と同じ
#   ゲートを通したため。DryRun は LLM を 1 本も起動せずに効きを測る唯一の経路なので必要）。
#   全文に対して当てると **DryRun 側の写しに当たり、実運転側を消しても通ってしまう**
#   (実測: NC M24〜M27 が BROKEN/SURVIVED になった)。
#   → 以下の配線 pin は **実運転の区間**（per-CSN ワーカージョブの開始以降）に限って当てる。
#   区間アンカーが消えたら測定不能として FAIL する（測り手不在で緑にしない）。
$realRegionAnchor = '$job = Start-Job -ScriptBlock {'
$realStart = $src.IndexOf($realRegionAnchor)
if ($realStart -lt 0) {
    Write-Output "[FAIL] 実運転区間のアンカーが見つからない: $realRegionAnchor"
    exit 1
}
$srcReal = $src.Substring($realStart)
# 닷소싱 자체(실행문)를 앵커로 쓴다. 단순히 "lib/preflight-target.ps1" 이 어딘가에 있는지로 보면
# 바로 위 주석에 같은 문자열이 있어 닷소싱 행을 지워도 통과해버린다(NC M24 로 실측 — 당해 생존).
$posDot   = $srcReal.IndexOf(". (Join-Path `$root 'lib/preflight-target.ps1')")
$posGate  = $srcReal.IndexOf('Test-GissuePreflightShouldSpawn $preflightMeasure')
$posStart = $srcReal.IndexOf('$repoMaintJob = Start-Job -InitializationScript')
Check 'h1 러너가 preflight lib 를 닷소싱한다(실행문 앵커)' ($posDot -gt 0) "pos=$posDot"
Check 'h2 러너에 게이트 호출이 있다'                   ($posGate -gt 0) "pos=$posGate"
Check 'h3 게이트가 REPO-MAINT Start-Job 보다 앞'       (($posGate -gt 0) -and ($posStart -gt 0) -and ($posGate -lt $posStart)) "gate=$posGate start=$posStart"
Check 'h4 Spawn=false 분기에서 Start-Job 을 건너뛴다'  ($srcReal -cmatch '(?s)if \(-not \$preflightDecision\.Spawn\) \{\s*\r?\n\s*# 여기서 return 하면') ''
Check 'h5 닷소싱이 게이트보다 앞'                      (($posDot -gt 0) -and ($posDot -lt $posGate)) "dot=$posDot gate=$posGate"
Check 'h6 게이트는 Measure 를 거쳐 판정한다'           ($srcReal.IndexOf('Measure-GissueRepoMaintTargets $preflightRepos') -gt 0) ''
Check 'h7 worktree 제외(주체크아웃 선별)를 거친다'     ($srcReal.IndexOf('Select-GissuePreflightPrimaryRepos') -gt 0) ''
# 삭감 장치가 처리 자체를 멈추는 원인이 되면 안 된다 — 프리플라이트 예외는 "기동" 쪽으로 폴백한다.
$posTry   = $srcReal.IndexOf('$preflightMeasure = $null
        $prevEapPf = $ErrorActionPreference')
Check 'h9 프리플라이트가 try/catch 로 감싸여 있다'       ($posTry -gt 0) "pos=$posTry"
Check 'h10 예외 시 Measure 는 null 로 남아 기동 쪽으로 간다' ($srcReal -match '(?s)\} catch \{[^}]*프리플라이트 자체가 실패') ''
Check 'h11 프리플라이트 구간만 ErrorActionPreference 를 낮춘다' ($srcReal.Contains("`$prevEapPf = `$ErrorActionPreference") -and $srcReal.Contains("`$ErrorActionPreference = 'Continue'")) ''
Check 'h12 끝나면 원래 값으로 되돌린다'                 ($srcReal -match '(?s)finally \{\s*\r?\n\s*\$ErrorActionPreference = \$prevEapPf') ''
Check 'h8 Start-Job 은 게이트 통과 후에만 나온다(단 1곳)' ((@([regex]::Matches($srcReal, [regex]::Escape('$repoMaintJob = Start-Job'))).Count) -eq 1) "count=$((@([regex]::Matches($srcReal, [regex]::Escape('$repoMaintJob = Start-Job'))).Count))"

# ── (i) P-5 부작용 금지: lib 코드에 쓰기 계열이 섞이면 FAIL ────────────────────
$libSrc  = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../lib/preflight-target.ps1') -Raw -Encoding UTF8
$libCode = (@($libSrc -split "`r?`n" | Where-Object { $_ -notmatch '^\s*#' }) -join "`n")
foreach ($bad in @('Out-File', 'Set-Content', 'Add-Content', 'New-Item', 'Remove-Item',
                   '--comment-file', 'gh pr edit', 'gh pr merge', 'gh pr comment', 'gh pr close',
                   'git commit', 'git push', 'git checkout', 'git stash drop', 'get-issue.sh')) {
    Check "i:'$bad' 가 lib 코드에 없다(읽기 전용)" (-not $libCode.Contains($bad)) '쓰기/부작용 명령이 프리플라이트에 섞였다'
}
Check 'i:gh 호출은 pr list 만'    (-not ($libCode -match 'gh (?!pr list)\w')) '읽기 전용이 아닌 gh 호출이 있다'
Check 'i:git 호출은 읽기 전용만'  ($libCode -match 'git -C \$RepoPath stash list') ''

# ── (i2) Detail 압축: 0 건 레포는 이름을 내지 않고, 0 이 아닌 레포만 명시한다 ────────
$m = Measure-GissueRepoMaintTargets $R2 (PortsOf 0 0 0 0)
Check 'i2-1 전부 0이면 레포 이름이 Detail 에 없다' (-not ((@($m.Detail) -join ' ') -match '/tmp/repoA')) "detail=$(@($m.Detail) -join ' ')"
Check 'i2-2 그래도 내역 5항목은 남는다'            ((@($m.Detail) -join ' ') -match 'repos=2 conflict=0 ci-fail=0 stash=0 recent-comment=0') "detail=$(@($m.Detail) -join ' ')"
$m = Measure-GissueRepoMaintTargets $R2 (PortsOf 1 0 0 0)
# -match 는 기본이 대소문자 무시다. 라벨 문자열을 핀으로 쓸 때 -match 를 쓰면
# '[0]CONFLICT@' 로 바꿔도 통과해버린다(NC M28 로 실측 — 당해 생존). -cmatch 로 고정한다.
Check 'i2-3 0 이 아닌 레포는 이름을 명시한다(대소문자까지)' ((@($m.Detail) -join ' ') -cmatch '\[0\]conflict@/tmp/repoA=1') "detail=$(@($m.Detail) -join ' ')"
$m = Measure-GissueRepoMaintTargets $R1 (PortsOf $null 0 0 0)
Check 'i2-4 판정불능 레포는 UNKNOWN 으로 명시된다'  ((@($m.Detail) -join ' ') -cmatch '\[0\]conflict@/tmp/repoA=UNKNOWN') "detail=$(@($m.Detail) -join ' ')"

# ── (j) 순수 분류 함수 pin — 네트워크 없이 fixture 로 직접 당긴다 ───────────────
# [0] conflict
function PR($n, $mg, $checks) { return [pscustomobject]@{ number = $n; mergeable = $mg; statusCheckRollup = $checks } }
$r = Measure-GissuePreflightConflictFromPrs @()
Check 'j1 열린 PR 0건 -> 확정 0'                 ($r.Ok -and $r.Count -eq 0) "ret=$($r | Out-String)"
$r = Measure-GissuePreflightConflictFromPrs @((PR 1 'MERGEABLE' @()), (PR 2 'MERGEABLE' @()))
Check 'j2 MERGEABLE 만이면 확정 0'                ($r.Ok -and $r.Count -eq 0) "count=$($r.Count)"
$r = Measure-GissuePreflightConflictFromPrs @((PR 1 'MERGEABLE' @()), (PR 2 'CONFLICTING' @()))
Check 'j3 CONFLICTING 1건을 센다'                 ($r.Ok -and $r.Count -eq 1) "count=$($r.Count)"
$r = Measure-GissuePreflightConflictFromPrs @((PR 1 'CONFLICTING' @()), (PR 2 'CONFLICTING' @()))
Check 'j4 CONFLICTING 2건을 센다'                 ($r.Ok -and $r.Count -eq 2) "count=$($r.Count)"
# UNKNOWN 을 "충돌 없음"으로 읽으면 계산 중인 충돌 PR 을 매 틱 놓친다 -> Unknown 이어야 한다.
$r = Measure-GissuePreflightConflictFromPrs @((PR 1 'MERGEABLE' @()), (PR 2 'UNKNOWN' @()))
Check 'j5 mergeable=UNKNOWN 은 0건이 아니라 Unknown' (-not $r.Ok) "ret=$($r | Out-String)"
Check 'j6 그 사유에 PR 번호가 들어간다'           ("$($r.Error)" -match '#2') "err=$($r.Error)"
$r = Measure-GissuePreflightConflictFromPrs @((PR 1 '' @()))
Check 'j7 mergeable 이 빈 값이어도 Unknown'        (-not $r.Ok) "ret=$($r | Out-String)"

# [E] CI 실패
function CK($concl, $state) { return [pscustomobject]@{ conclusion = $concl; state = $state } }
$r = Measure-GissuePreflightCiFailFromPrs @((PR 1 'MERGEABLE' @((CK 'SUCCESS' 'SUCCESS'))))
Check 'j8 전부 SUCCESS 면 확정 0'                 ($r.Ok -and $r.Count -eq 0) "count=$($r.Count)"
$r = Measure-GissuePreflightCiFailFromPrs @((PR 1 'MERGEABLE' @((CK 'SUCCESS' 'SUCCESS'), (CK 'FAILURE' ''))))
Check 'j9 conclusion=FAILURE 를 센다'             ($r.Ok -and $r.Count -eq 1) "count=$($r.Count)"
$r = Measure-GissuePreflightCiFailFromPrs @((PR 1 'MERGEABLE' @((CK '' 'ERROR'))))
Check 'j10 state=ERROR 를 센다'                   ($r.Ok -and $r.Count -eq 1) "count=$($r.Count)"
$r = Measure-GissuePreflightCiFailFromPrs @((PR 1 'MERGEABLE' @((CK 'TIMED_OUT' ''))))
Check 'j11 TIMED_OUT 도 실패로 센다'              ($r.Ok -and $r.Count -eq 1) "count=$($r.Count)"
$r = Measure-GissuePreflightCiFailFromPrs @((PR 1 'MERGEABLE' @((CK 'CANCELLED' ''))))
Check 'j12 CANCELLED 도 실패로 센다'              ($r.Ok -and $r.Count -eq 1) "count=$($r.Count)"
$r = Measure-GissuePreflightCiFailFromPrs @((PR 1 'MERGEABLE' @((CK 'STARTUP_FAILURE' ''))))
Check 'j13 STARTUP_FAILURE 도 실패로 센다'        ($r.Ok -and $r.Count -eq 1) "count=$($r.Count)"
# pending/in_progress 는 "결과 대기" 라 대상이 아니다(프롬프트 [E] 2 와 같은 집합).
$r = Measure-GissuePreflightCiFailFromPrs @((PR 1 'MERGEABLE' @((CK '' 'PENDING'), (CK '' 'IN_PROGRESS'))))
Check 'j14 PENDING/IN_PROGRESS 는 세지 않는다'    ($r.Ok -and $r.Count -eq 0) "count=$($r.Count)"
# PR 1건에 실패 체크가 여러 개여도 "PR 1건" 으로 센다(기동 여부 판단에는 PR 단위가 맞다).
$r = Measure-GissuePreflightCiFailFromPrs @((PR 1 'MERGEABLE' @((CK 'FAILURE' ''), (CK 'FAILURE' ''))))
Check 'j15 같은 PR 의 실패 체크 복수는 1건'       ($r.Ok -and $r.Count -eq 1) "count=$($r.Count)"
$r = Measure-GissuePreflightCiFailFromPrs @((PR 1 'MERGEABLE' @((CK 'FAILURE' ''))), (PR 2 'MERGEABLE' @((CK 'FAILURE' ''))))
Check 'j16 서로 다른 PR 2건은 2건'                ($r.Ok -and $r.Count -eq 2) "count=$($r.Count)"
$r = Measure-GissuePreflightCiFailFromPrs @((PR 1 'MERGEABLE' $null))
Check 'j17 rollup 이 null 이면 0'                 ($r.Ok -and $r.Count -eq 0) "count=$($r.Count)"
$r = Measure-GissuePreflightCiFailFromPrs @((PR 1 'MERGEABLE' @((CK 'failure' ''))))
Check 'j18 소문자 conclusion 도 센다(대소문자 무시)' ($r.Ok -and $r.Count -eq 1) "count=$($r.Count)"

# [F] stash 메시지
$r = Measure-GissuePreflightStashFromLines @()
Check 'j19 stash 0건 -> 확정 0'                   ($r.Ok -and $r.Count -eq 0) "count=$($r.Count)"
$r = Measure-GissuePreflightStashFromLines @('stash@{0}: On dev: auto-unblock giip-4528 잔해')
Check 'j20 On <branch>: auto-unblock 을 센다'     ($r.Ok -and $r.Count -eq 1) "count=$($r.Count)"
$r = Measure-GissuePreflightStashFromLines @('stash@{0}: auto-unblock 잔해')
Check 'j21 branch 없는 형식도 센다'               ($r.Ok -and $r.Count -eq 1) "count=$($r.Count)"
$r = Measure-GissuePreflightStashFromLines @('stash@{0}: WIP on dev: auto-unblock x')
Check 'j22 WIP on <branch>: 형식도 센다'          ($r.Ok -and $r.Count -eq 1) "count=$($r.Count)"
# 선두 일치로 보지 않으면 무관한 stash 를 집어 LLM 을 헛기동시킨다.
$r = Measure-GissuePreflightStashFromLines @('stash@{0}: On dev: 수동 보관 (auto-unblock 아님)')
Check 'j23 메시지 중간의 auto-unblock 은 세지 않는다' ($r.Ok -and $r.Count -eq 0) "count=$($r.Count)"
$r = Measure-GissuePreflightStashFromLines @('stash@{0}: On dev: auto-unblocked-ish')
Check 'j24 "auto-unblock" 뒤에 공백이 없으면 세지 않는다' ($r.Ok -and $r.Count -eq 0) "count=$($r.Count)"
$r = Measure-GissuePreflightStashFromLines @('stash@{0}: On dev: auto-unblock a', 'stash@{1}: On dev: 기타', 'stash@{2}: auto-unblock b')
Check 'j25 혼재 시 해당 건만 센다(2건)'           ($r.Ok -and $r.Count -eq 2) "count=$($r.Count)"

if ($fail -gt 0) { Write-Output "FAILED: $fail"; exit 1 }
Write-Output 'ALL PASS'
