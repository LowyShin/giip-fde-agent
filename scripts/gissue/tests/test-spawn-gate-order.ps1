# test-spawn-gate-order.ps1 — lib/spawn-gate-audit.ps1 の判定契約 S-1〜S-8 と、
#   run-gissue-claude.ps1 への適用結果を pin する（giip 4806）
#
# このテストは run-repo-gates.ps1 が `tests/test-*.ps1` として自動発見し、
# CI(.github/workflows/repo-gates.yml)が PR / push(main) で実行する。
#
# ⚠ 先行ガード(test-preflight-target.ps1 / test-engine-backoff.ps1)は**置き換えず併走**させる。
#   そちらは「ゲート呼び出しが在るか・文字位置が前か」を見ており、こちらは
#   「spawn 点を全数列挙して、各点がゲートの**内側**に在るか」を木で見る。被覆は合併で測る。
#
# 外部依存 0（ネットワーク・プロセス起動・ファイル書き込みなし）。

$ErrorActionPreference = 'Continue'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch { }

$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Path }
# 닷소싱の実行文そのものをアンカーにする(ファイル名が「どこかに在るか」で見ると、すぐ上の
# コメントに同じ文字列が在るせいで닷소싱行を消しても通る — giip 4804/4805 の NC で実測)。
. (Join-Path $here '../lib/spawn-gate-audit.ps1')

$fail = 0
$pass = 0
function Check([string]$name, [bool]$cond, [string]$detail) {
    if ($cond) { $script:pass++; Write-Output "[PASS] $name" }
    else { $script:fail++; Write-Output "[FAIL] $name $detail" }
}

# ══ (a) S-1/S-3: 測り手不在・解析不能を「違反 0 件」と読まない ════════════════
$r = Get-GissueSpawnGateAudit '' '(empty)'
Check 'a1 空ソースは Ok=false' (-not $r.Ok) "reason=$($r.Reason)"
$r = Get-GissueSpawnGateAudit 'if ($x) {' '(broken)'
Check 'a2 構文エラーは Ok=false' (-not $r.Ok) "reason=$($r.Reason)"
Check 'a2b その理由は構文エラーと明示される' ($r.Reason.Contains('構文エラー')) "reason=$($r.Reason)"
$r = Get-GissueSpawnGateAudit 'Write-Output "nothing to spawn here"' '(no-site)' @()
Check 'a3 spawn 点 0 件は Ok=false(rule 42)' (-not $r.Ok) "reason=$($r.Reason)"
$r = Get-GissueSpawnGateAuditForFile '/nonexistent/giip4806/none.ps1'
Check 'a4 ファイル不在は Ok=false' (-not $r.Ok) "reason=$($r.Reason)"

# ══ (b) S-2: spawn 点の検出 ═══════════════════════════════════════════════════
# ヒアストリングの中の同名テキストは**コマンドではない**(文字列検索なら誤検出する所)。
$srcHereString = @'
$init = [scriptblock]::Create(@"
function Invoke-GissueEngine {
  & claude -p --model x
}
"@)
$dummy = 1
'@
$r = Get-GissueSpawnGateAudit $srcHereString '(herestring)' @()
Check 'b1 ヒアストリング内の claude/Start-Job は spawn 点でない' ($r.Reason.Contains('0 件')) "sites=$(@($r.Sites).Count) reason=$($r.Reason)"

$srcTwo = @'
$fallbackPrompt | & claude -p --model a
$p2 = $prompt2 | & claude -p --model b
'@
$reg2 = @(
    @{ Key = 'claude-cli|<top>|fallbackPrompt'; Gated = 'none'; Why = 't' },
    @{ Key = 'claude-cli|<top>|prompt2';        Gated = 'none'; Why = 't' }
)
$r = Get-GissueSpawnGateAudit $srcTwo '(two-cli)' $reg2
# ここは S-4(レジスタ照合)だけを見る。この fixture に DryRun 分岐は無いので S-7 は別に当てる((f) 節)。
$b2keys = @(@($r.Sites) | ForEach-Object { $_.Key })
Check 'b2 同じ関数内の 2 本を別々のキーで識別する' (@($r.Sites).Count -eq 2 -and ($b2keys -ccontains 'claude-cli|<top>|fallbackPrompt') -and ($b2keys -ccontains 'claude-cli|<top>|prompt2')) "keys=$($b2keys -join ', ')"
Check 'b2b その 2 本は S-4 違反を出さない' (-not ((@($r.Violations) -join ' ').Contains('S-4'))) "v=$(@($r.Violations) -join ' / ')"

$srcJobNoEngine = @'
$j = Start-Job -ScriptBlock { Write-Output "no engine here" }
'@
$r = Get-GissueSpawnGateAudit $srcJobNoEngine '(job-no-engine)' @()
Check 'b3 エンジンを呼ばない Start-Job は spawn 点でない' ($r.Reason.Contains('0 件')) "sites=$(@($r.Sites).Count)"

# 祖先の走査は**関数境界で止める**。止めないと、関数の中の起動が外側の代入まで登って
# 別々の起動点が同じキーに潰れる(NC M10 で実測・当該生存)。
# ここはパイプラインでない claude 起動を使う — パイプライン規則が先に当たると境界の効きが測れない。
$srcBoundary = @'
$assigned = & { function F { & claude -p --model a } }
'@
$r = Get-GissueSpawnGateAudit $srcBoundary '(boundary)' @(@{ Key = 'claude-cli|F|<none>'; Gated = 'none'; Why = 't' })
$bKeys = @(@($r.Sites) | ForEach-Object { $_.Key })
Check 'b4 関数の中の起動は外側の代入名を拾わない' ($bKeys -ccontains 'claude-cli|F|<none>') "keys=$($bKeys -join ', ')"

# ══ (c) S-4: レジスタ照合は両方向 ════════════════════════════════════════════
$srcOne = '$fallbackPrompt | & claude -p --model a'
$r = Get-GissueSpawnGateAudit $srcOne '(unregistered)' @(@{ Key = 'claude-cli|<top>|somethingElse'; Gated = 'none'; Why = 't' })
Check 'c1 未登録の起動点は違反' ((-not $r.Ok) -and ((@($r.Violations) -join ' ').Contains('未登録'))) "v=$(@($r.Violations) -join ' / ')"
# ⚠ '見つからない' だけで当ててはいけない — S-7 の文面(「`-DryRun` 分岐が見つからない」)にも
#   同じ語が在るので、S-4 側を消しても通ってしまう(NC M13 で実測・当該生存)。
#   レジスタ照合であることが判る語まで含めて当てる。
Check 'c2 消えた登録点も違反' ((@($r.Violations) -join ' ').Contains('S-4: レジスタの')) "v=$(@($r.Violations) -join ' / ')"

# ══ (d) S-5: 順序ではなく内包で見る（これが先行ガードに無い被覆） ═════════════
$regRepo = @(@{ Key = 'engine-job|<top>|repoMaintJob'; Gated = 'preflight'; Why = 't' })
$srcInside = @'
$preflightDecision = Test-GissuePreflightShouldSpawn $m 'REPO-MAINT'
if (-not $preflightDecision.Spawn) {
    Write-Output "skip"
} else {
    $repoMaintJob = Start-Job -ScriptBlock { Invoke-GissueEngine -PromptText $p }
}
if ($DryRun) {
    $x = Test-GissueBackoffActive $f $n 'REPO-MAINT'
    $y = Resolve-GissueHRecheckHoursBack $f $c $n 2
    $z = Measure-GissueRepoMaintTargets $repos $ports
    $w = Test-GissuePreflightShouldSpawn $z 'REPO-MAINT'
}
'@
$r = Get-GissueSpawnGateAudit $srcInside '(inside-else)' $regRepo
Check 'd1 Else 節の内側にある spawn は通る' ($r.Ok) "v=$(@($r.Violations) -join ' / ')"

# ★ 当て先の核心: ゲート呼び出しを前に残したまま spawn を分岐の**外**へ出す。
#   「ゲートが spawn より前」は成立し続けるので、先行ガードの順序 pin は素通りする。
$srcOutside = @'
$preflightDecision = Test-GissuePreflightShouldSpawn $m 'REPO-MAINT'
if (-not $preflightDecision.Spawn) {
    Write-Output "skip"
} else {
    Write-Output "would spawn"
}
$repoMaintJob = Start-Job -ScriptBlock { Invoke-GissueEngine -PromptText $p }
if ($DryRun) {
    $x = Test-GissueBackoffActive $f $n 'REPO-MAINT'
    $y = Resolve-GissueHRecheckHoursBack $f $c $n 2
    $z = Measure-GissueRepoMaintTargets $repos $ports
    $w = Test-GissuePreflightShouldSpawn $z 'REPO-MAINT'
}
'@
$r = Get-GissueSpawnGateAudit $srcOutside '(outside-else)' $regRepo
Check 'd2 分岐の外へ出した spawn は違反(順序では捕まらない型)' ((-not $r.Ok) -and ((@($r.Violations) -join ' ').Contains('S-5'))) "v=$(@($r.Violations) -join ' / ')"

# then 節(skip 側)に置くのも違反 — 「0 件のときに起動する」逆配線を通さない。
$srcThen = $srcInside.Replace("if (-not `$preflightDecision.Spawn) {`n    Write-Output `"skip`"`n} else {`n    `$repoMaintJob = Start-Job -ScriptBlock { Invoke-GissueEngine -PromptText `$p }`n}",
                              "if (-not `$preflightDecision.Spawn) {`n    `$repoMaintJob = Start-Job -ScriptBlock { Invoke-GissueEngine -PromptText `$p }`n} else {`n    Write-Output `"spawn`"`n}")
$r = Get-GissueSpawnGateAudit $srcThen '(then-branch)' $regRepo
Check 'd3 skip 側(then 節)に置いた spawn は違反' ((-not $r.Ok) -and ((@($r.Violations) -join ' ').Contains('S-5'))) "v=$(@($r.Violations) -join ' / ')"

# S-8: 大小だけ違う綴りは PowerShell では**同じプロパティ**なので、赤くしてはいけない
#   (動きが同じものを赤くするガードは「直す理由のない赤」を出し続ける → 偽陽性側の pin)。
$srcCaseOnly = $srcInside.Replace('if (-not $preflightDecision.Spawn) {', 'if (-not $preflightDecision.SPAWN) {')
$r = Get-GissueSpawnGateAudit $srcCaseOnly '(cond-case)' $regRepo
Check 'd4 大小だけ違う綴りは同じゲートと認める(偽陽性を作らない)' ($r.Ok) "v=$(@($r.Violations) -join ' / ')"
# ただし**別の名前**なら内包と認めない(ゲートを別物に差し替える改変を通さない)。
$srcOtherCond = $srcInside.Replace('if (-not $preflightDecision.Spawn) {', 'if (-not $otherDecision.Spawn) {')
$r = Get-GissueSpawnGateAudit $srcOtherCond '(cond-other)' $regRepo
Check 'd4b 別名のゲートでは内包と認めない' ((-not $r.Ok) -and ((@($r.Violations) -join ' ').Contains('S-5'))) "v=$(@($r.Violations) -join ' / ')"
# 無関係な if の Else に入れただけでは「プリフライトの内側」ではない。
$srcUnrelatedIf = @'
$preflightDecision = Test-GissuePreflightShouldSpawn $m 'REPO-MAINT'
if ($somethingElse) {
    Write-Output "a"
} else {
    $repoMaintJob = Start-Job -ScriptBlock { Invoke-GissueEngine -PromptText $p }
}
if ($DryRun) {
    $x = Test-GissueBackoffActive $f $n 'REPO-MAINT'
    $y = Resolve-GissueHRecheckHoursBack $f $c $n 2
    $z = Measure-GissueRepoMaintTargets $repos $ports
    $w = Test-GissuePreflightShouldSpawn $z 'REPO-MAINT'
}
'@
$r = Get-GissueSpawnGateAudit $srcUnrelatedIf '(unrelated-if)' $regRepo
Check 'd5 無関係な if の Else は内包と認めない' ((-not $r.Ok) -and ((@($r.Violations) -join ' ').Contains('S-5'))) "v=$(@($r.Violations) -join ' / ')"

# Else 節が無いゲート(= 0 件でも通り抜ける書き方)を内包と認めない。
#   `$null -ne $parent.ElseClause` の検査を外すと、Else が無くても内包扱いになる
#   (null の Extent が 0 と読まれて範囲比較が成立する — NC M16 で実測・当該生存)。
$srcNoElse = @'
$preflightDecision = Test-GissuePreflightShouldSpawn $m 'REPO-MAINT'
if (-not $preflightDecision.Spawn) {
    $repoMaintJob = Start-Job -ScriptBlock { Invoke-GissueEngine -PromptText $p }
}
if ($DryRun) {
    $x = Test-GissueBackoffActive $f $n 'REPO-MAINT'
    $y = Resolve-GissueHRecheckHoursBack $f $c $n 2
    $z = Measure-GissueRepoMaintTargets $repos $ports
    $w = Test-GissuePreflightShouldSpawn $z 'REPO-MAINT'
}
'@
$r = Get-GissueSpawnGateAudit $srcNoElse '(no-else)' $regRepo
Check 'd6 Else 節が無いゲートは内包と認めない' ((-not $r.Ok) -and ((@($r.Violations) -join ' ').Contains('S-5'))) "v=$(@($r.Violations) -join ' / ')"

# ══ (e) S-6: per-issue は「ループ内で break する判定が spawn より前」 ═════════
$regIssue = @(@{ Key = 'engine-job|<top>|innerJob'; Gated = 'backoff-break'; Why = 't' })
$dryTail = @'
if ($DryRun) {
    $x = Test-GissueBackoffActive $f $n 'REPO-MAINT'
    $y = Resolve-GissueHRecheckHoursBack $f $c $n 2
    $z = Measure-GissueRepoMaintTargets $repos $ports
    $w = Test-GissuePreflightShouldSpawn $z 'REPO-MAINT'
}
'@
$srcBreakOk = @'
for ($qi = 0; $qi -lt $n; $qi++) {
    if ($engineBlockedThisTick) {
        Write-Output "[BACKOFF-BREAK] stop"
        break
    }
    $innerJob = Start-Job -ScriptBlock { Invoke-GissueEngine -PromptText $p }
}
'@ + "`n" + $dryTail
$r = Get-GissueSpawnGateAudit $srcBreakOk '(break-ok)' $regIssue
Check 'e1 ループ先頭の break 判定があれば通る' ($r.Ok) "v=$(@($r.Violations) -join ' / ')"

$srcBreakAfter = @'
for ($qi = 0; $qi -lt $n; $qi++) {
    $innerJob = Start-Job -ScriptBlock { Invoke-GissueEngine -PromptText $p }
    if ($engineBlockedThisTick) {
        Write-Output "[BACKOFF-BREAK] stop"
        break
    }
}
'@ + "`n" + $dryTail
$r = Get-GissueSpawnGateAudit $srcBreakAfter '(break-after)' $regIssue
Check 'e2 break 判定が spawn の後なら違反(1本目が空振りする)' ((-not $r.Ok) -and ((@($r.Violations) -join ' ').Contains('S-6'))) "v=$(@($r.Violations) -join ' / ')"

$srcBreakNoBreak = @'
for ($qi = 0; $qi -lt $n; $qi++) {
    if ($engineBlockedThisTick) {
        Write-Output "[BACKOFF-BREAK] stop"
    }
    $innerJob = Start-Job -ScriptBlock { Invoke-GissueEngine -PromptText $p }
}
'@ + "`n" + $dryTail
$r = Get-GissueSpawnGateAudit $srcBreakNoBreak '(log-only)' $regIssue
Check 'e3 ログだけ出して break しないのは違反(文字列 pin が通す型)' ((-not $r.Ok) -and ((@($r.Violations) -join ' ').Contains('S-6'))) "v=$(@($r.Violations) -join ' / ')"

$srcNoLoop = @'
if ($engineBlockedThisTick) { break }
$innerJob = Start-Job -ScriptBlock { Invoke-GissueEngine -PromptText $p }
'@ + "`n" + $dryTail
$r = Get-GissueSpawnGateAudit $srcNoLoop '(no-loop)' $regIssue
Check 'e4 ループの外なら内包と認めない' (-not $r.Ok) "v=$(@($r.Violations) -join ' / ')"

# 別条件で break しているだけでは「即死中は起動しない」にならない。
$srcOtherBreak = @'
for ($qi = 0; $qi -lt $n; $qi++) {
    if ($somethingElse) { break }
    $innerJob = Start-Job -ScriptBlock { Invoke-GissueEngine -PromptText $p }
}
'@ + "`n" + $dryTail
$r = Get-GissueSpawnGateAudit $srcOtherBreak '(other-break)' $regIssue
Check 'e5 別条件の break では S-6 を満たさない' ((-not $r.Ok) -and ((@($r.Violations) -join ' ').Contains('S-6'))) "v=$(@($r.Violations) -join ' / ')"

# ══ (f) S-7: DryRun 分岐のパリティ ═══════════════════════════════════════════
$r = Get-GissueSpawnGateAudit ($srcInside.Replace('$w = Test-GissuePreflightShouldSpawn $z ''REPO-MAINT''', '# removed')) '(dry-missing)' $regRepo
Check 'f1 DryRun 分岐が判定を 1 つ欠いたら違反' ((-not $r.Ok) -and ((@($r.Violations) -join ' ').Contains('S-7'))) "v=$(@($r.Violations) -join ' / ')"
$r = Get-GissueSpawnGateAudit ($srcInside.Replace("if (`$DryRun) {", 'if ($false) {')) '(dry-gone)' $regRepo
# ⚠ 'S-7' だけで当てると、分岐不在の早期 return を外しても(アンカー 4 本が個別に違反を立てるので)
#   同じ 'S-7' が出て通ってしまう(NC M26 で実測・当該生存=害を生まない等価 mutant)。
#   「分岐そのものが無い」という**別の診断**が出ることまで当てる。
Check 'f2 DryRun 分岐そのものが消えたら違反' ((-not $r.Ok) -and ((@($r.Violations) -join ' ').Contains('分岐が見つからない'))) "v=$(@($r.Violations) -join ' / ')"
# `-not $DryRun`(実運転側)を DryRun 分岐と誤認しないこと。
$r = Get-GissueSpawnGateAudit ($srcInside.Replace("if (`$DryRun) {", 'if (-not $DryRun) {')) '(not-dry)' $regRepo
Check 'f3 `-not $DryRun` 側を DryRun 分岐と読まない' ((-not $r.Ok) -and ((@($r.Violations) -join ' ').Contains('S-7'))) "v=$(@($r.Violations) -join ' / ')"

# ══ (g) 実物適用 — run-gissue-claude.ps1 ═════════════════════════════════════
$runner = Join-Path $here '../run-gissue-claude.ps1'
$res = Get-GissueSpawnGateAuditForFile ((Resolve-Path -LiteralPath $runner).Path)
foreach ($v in @($res.Violations)) { Write-Output "    [違反] $v" }
Check 'g1 実物が契約を満たす' ($res.Ok) "reason=$($res.Reason)"
$keys = @(@($res.Sites) | ForEach-Object { $_.Key })
Check 'g2 REPO-MAINT の起動点が在る'   ($keys -ccontains 'engine-job|<top>|repoMaintJob') "keys=$($keys -join ', ')"
Check 'g3 per-issue の起動点が在る'    ($keys -ccontains 'engine-job|<top>|innerJob') "keys=$($keys -join ', ')"
Check 'g4 エンジン本体の 2 本が在る'   (($keys -ccontains 'claude-cli|Invoke-GissueEngine|PromptText') -and ($keys -ccontains 'claude-cli|Invoke-GissueEngine|fallbackPrompt')) "keys=$($keys -join ', ')"
# レジスタと実物の件数が一致していること。片方が増減したら上の両方向照合で落ちる。
Check 'g5 起動点はレジスタと同数'      (@($res.Sites).Count -eq @(Get-GissueSpawnGateRegistry).Count) "sites=$(@($res.Sites).Count) reg=$(@(Get-GissueSpawnGateRegistry).Count)"
Check 'g6 ゲート対象の 2 点が両方 Pass' ((@(@($res.Sites) | Where-Object { $_.Gated -ne 'none' -and $_.Pass }).Count) -eq 2) "gated=$(@(@($res.Sites) | Where-Object { $_.Gated -ne 'none' }) | ForEach-Object { $_.Key + '=' + $_.Pass })"

# ══ (h) 緑対照 — これで赤くなるなら過敏(契約でない変更) ══════════════════════
#   判定に関与しない変更では落ちないこと。落ちるなら当て先が広すぎる。
$srcGreen = $srcInside + "`n# このコメントは判定に関与しない`nWrite-Output 'unrelated'`n"
$r = Get-GissueSpawnGateAudit $srcGreen '(green-comment)' $regRepo
Check 'h1 緑対照: 無関係な行の追加では落ちない' ($r.Ok) "v=$(@($r.Violations) -join ' / ')"
$srcGreen2 = $srcInside.Replace('Write-Output "skip"', 'Write-Output "skip (reason=no-target)"')
$r = Get-GissueSpawnGateAudit $srcGreen2 '(green-msg)' $regRepo
Check 'h2 緑対照: skip メッセージの文面変更では落ちない' ($r.Ok) "v=$(@($r.Violations) -join ' / ')"

Write-Output ''
Write-Output "PASS=$pass FAIL=$fail"
if ($fail -gt 0) { Write-Output "FAILED: $fail"; exit 1 }
Write-Output 'ALL PASS'
exit 0
