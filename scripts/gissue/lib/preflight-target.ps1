# preflight-target.ps1 — LLM セッション起動前の「処理対象0件」判定（giip 4804）
#
# 用途
#   run-gissue-claude.ps1 Phase 1 の (A) 저장소 정비(REPO-MAINT) セッションは、これまで
#   **対象の有無を一切見ずに毎ティック LLM を起動**していた。プロンプト本文($BlockRepoMaint)が
#   「[0] 열린 conflict 가 하나도 없으면 조용히 건너뛴다 / [F] stash 가 하나도 없으면 조용히
#   건너뛴다 / [H] 대상 이슈가 하나도 없으면 조용히 건너뛴다」と LLM に指示していたため、
#   **「対象0件」の確認そのものを LLM にやらせていた**。その1回が実測中央値 1,456,098 トークン
#   (giip-4804 ベースライン: smartorder-works/.agent/metrics/scheduler-baseline-giip-4804.md)。
#   同じ判定は gh / git / list-issues.js の読み取りだけで完結するので、ここで先に判定し、
#   0件なら LLM を起動しない。
#
# 処理内容 / 保存先 / 消費先（コード文書化規則: 用途・処理・保存・消費を具体的に）
#   - このファイルは **何も書き込まない**(ファイル・DB・ネットワーク書き込み 0 件)。
#     外部参照はすべて読み取り専用コマンド(gh pr list / git stash list / list-issues.js --json)。
#   - 保存先: なし(判定結果をオブジェクトで返すだけ)。
#   - 消費先: run-gissue-claude.ps1 Phase 1 の REPO-MAINT 起動直前、
#             tests/test-preflight-target.ps1(偽ポートで全経路検証)。
#
# 判定契約（P-1〜P-6 — ここを崩すと「測り手不在で永久に緑」になる）
#   P-1 0件と断定できるのは **全チェックが確定で0を返したときだけ**。1件でも判定不能が
#       混ざったら Unknown=true とし、**起動する側**に倒す(取りこぼしは作らない)。
#   P-2 判定不能を黙って skip しない。Unknown のときは必ず警告行を出す
#       (`[PREFLIGHT][WARN] ... → 従来どおり起動`)。静かな exit 0 を作らない。
#   P-3 Spawn=false のときのログ行は固定フォーマット
#       `SKIP reason=no-target job=<name> count=0`。受け入れ条件がこの行をログで示すことを
#       要求しているため、文字列は契約であって自由書式ではない。
#   P-4 ポートが 1 本も確定値を返さなかった場合(全滅)は 0件ではなく Unknown。
#       「測り手が全員いない」状態を 0件と読み替えない。
#   P-5 副作用禁止。ポート実装も読み取り専用コマンドだけを使う。
#   P-6 **ポートの戻り値は必ず結果オブジェクト**(New-GissuePreflightCount /
#       New-GissuePreflightUnknown)。PowerShell は scriptblock から返した空配列 @() を
#       $null に畳んでしまうため、`$null = 判定不能` という設計は「確定0件」と
#       「gh が 401 で落ちた」を **原理的に区別できない**(InvokeReturnAsIs でも畳まれる)。
#       区別できない設計にすると「gh が死んでいる間ずっと 0 件扱いで LLM が起動しない」か
#       「常に起動して削減が効かない」のどちらかに静かに倒れる。だから Ok を明示で持たせる。
#       契約違反の戻り値(素の配列・$null 等)は 0件ではなく Unknown として扱う。
#
# PowerShell 5.1 互換(`??` / 三項演算子 / null 条件演算子は使わない — 5.1 パーサが
# ファイル全体を落とすため。scripts/gissue/check-ps1-parse.ps1 がこれを検査する)。

$script:GissuePreflightSkipFormat = 'SKIP reason=no-target job={0} count=0'

# ── ポート戻り値のコンストラクタ（P-6） ───────────────────────────────────────
function New-GissuePreflightCount([int]$Count) {
    return [pscustomobject]@{ GissuePreflight = $true; Ok = $true; Count = $Count; Error = '' }
}
function New-GissuePreflightUnknown([string]$Reason) {
    $r = $Reason
    if (-not $r) { $r = '理由不明' }
    return [pscustomobject]@{ GissuePreflight = $true; Ok = $false; Count = 0; Error = $r }
}
function Test-GissuePreflightResultShape($Value) {
    if ($null -eq $Value) { return $false }
    $p = $Value.PSObject.Properties
    if (-not $p) { return $false }
    foreach ($n in @('GissuePreflight', 'Ok', 'Count', 'Error')) {
        if (-not ($p.Name -contains $n)) { return $false }
    }
    return [bool]$Value.GissuePreflight
}

# ポート1本を呼び、結果オブジェクトに正規化する。例外・契約違反はすべて Unknown に畳む。
function Invoke-GissuePreflightPort($Port, $Label, $Arg = $null) {
    if ($null -eq $Port) { return New-GissuePreflightUnknown "port 未指定($Label)" }
    try {
        $raw = $null
        if ($null -eq $Arg) { $raw = $Port.InvokeReturnAsIs() }
        else { $raw = $Port.InvokeReturnAsIs($Arg) }
        if (-not (Test-GissuePreflightResultShape $raw)) {
            # P-6: 素の配列や $null は「確定0件」と読まない。契約違反として Unknown。
            return New-GissuePreflightUnknown "port 契約違反($Label): 結果オブジェクトを返していない"
        }
        if (-not $raw.Ok) {
            $e = "$($raw.Error)"
            if (-not $e) { $e = '判定不能' }
            return New-GissuePreflightUnknown "$Label : $e"
        }
        return New-GissuePreflightCount ([int]$raw.Count)
    } catch {
        return New-GissuePreflightUnknown "$Label 例外: $($_.Exception.Message)"
    }
}

# REPO-MAINT([0]/[E]/[F]/[H]) の対象件数を数える。
#   -RepoPaths : [0]/[E]/[F] を見る git レポのパス配列(主チェックアウトのみ。worktree は
#                Select-GissuePreflightPrimaryRepos で除外する — stash/PR は git common dir
#                共有のため二重計上になるうえ、他セッションが居座る worktree に触る理由がない)
#   -Ports     : ハッシュテーブル。すべて読み取り専用で、戻り値は P-6 の結果オブジェクト。
#                ListConflictingPrs      { param($repo) }
#                ListFailingCiPrs        { param($repo) }
#                ListAutoUnblockStash    { param($repo) }
#                ListRecentCommentIssues { }
function Measure-GissueRepoMaintTargets($RepoPaths, $Ports) {
    $m = [pscustomobject]@{
        Conflicting    = 0
        FailingCi      = 0
        OrphanStash    = 0
        RecentComment  = 0
        Total          = 0
        Unknown        = $false
        UnknownReasons = @()
        Detail         = @()
        PortsResolved  = 0
    }
    if ($null -eq $Ports) { $Ports = @{} }
    $repos = @($RepoPaths | Where-Object { $_ })

    foreach ($repo in $repos) {
        foreach ($spec in @(
            @{ Key = 'ListConflictingPrs';   Label = "[0]conflict@$repo"; Field = 'Conflicting' },
            @{ Key = 'ListFailingCiPrs';     Label = "[E]ci-fail@$repo";  Field = 'FailingCi' },
            @{ Key = 'ListAutoUnblockStash'; Label = "[F]stash@$repo";    Field = 'OrphanStash' }
        )) {
            $r = Invoke-GissuePreflightPort $Ports[$spec.Key] $spec.Label $repo
            if ($r.Ok) {
                $m.PortsResolved++
                $m."$($spec.Field)" = $m."$($spec.Field)" + $r.Count
                # Detail はログ1行に載る。レポ数 x 3 本を全部並べると数千文字になって読めないので、
                # 0 件は集計(下の Total 行)に任せ、**0 でないレポだけ**を名指しする。
                if ($r.Count -gt 0) { $m.Detail += "$($spec.Label)=$($r.Count)" }
            } else {
                $m.Unknown = $true
                $m.UnknownReasons += $r.Error
                $m.Detail += "$($spec.Label)=UNKNOWN"
            }
        }
    }

    # [H] は CSN 単位(レポ非依存)
    $h = Invoke-GissuePreflightPort $Ports['ListRecentCommentIssues'] '[H]recent-comment'
    if ($h.Ok) {
        $m.PortsResolved++
        $m.RecentComment = $h.Count
        # 集約行(recent-comment=N)と重複するので、0 件のときは名指ししない。
        if ($h.Count -gt 0) { $m.Detail += "[H]recent-comment=$($h.Count)" }
    } else {
        $m.Unknown = $true
        $m.UnknownReasons += $h.Error
        $m.Detail += '[H]recent-comment=UNKNOWN'
    }

    # P-4: ポートが1本も確定しなかったら 0件ではなく Unknown
    if ($m.PortsResolved -le 0) {
        $m.Unknown = $true
        if (-not ($m.UnknownReasons -contains 'ポートが1本も確定値を返していない')) {
            $m.UnknownReasons += 'ポートが1本も確定値を返していない'
        }
    }

    $m.Total = $m.Conflicting + $m.FailingCi + $m.OrphanStash + $m.RecentComment
    # 内訳は常に 1 行で残す(0 件でも残す — 「測ったが 0 だった」と「測っていない」をログで区別するため)。
    $m.Detail = @("repos=$(@($repos).Count)",
                  "conflict=$($m.Conflicting)", "ci-fail=$($m.FailingCi)",
                  "stash=$($m.OrphanStash)", "recent-comment=$($m.RecentComment)") + @($m.Detail)
    return $m
}

# 起動するか否か。P-1/P-2/P-3 をここで固定する。
# 返り値: @{ Spawn=bool; Reason='has-target'|'no-target'|'preflight-unknown'; LogLines=@(string) }
function Test-GissuePreflightShouldSpawn($Measure, $JobName = 'REPO-MAINT') {
    if ($null -eq $Measure) {
        # 測り手そのものが無い。0件と読み替えず、必ず起動して警告する(P-2/P-4)。
        return @{
            Spawn    = $true
            Reason   = 'preflight-unknown'
            LogLines = @("[PREFLIGHT][WARN] job=$JobName 判定結果が null — 対象0件とは断定できないため従来どおり起動する")
        }
    }
    $lines = @()
    $detail = ''
    if (@($Measure.Detail).Count -gt 0) { $detail = ' ' + (@($Measure.Detail) -join ' ') }

    if ($Measure.Total -gt 0) {
        $lines += "[PREFLIGHT] job=$JobName count=$($Measure.Total) → 起動する$detail"
        if ($Measure.Unknown) {
            $lines += "[PREFLIGHT][WARN] job=$JobName 一部判定不能: $(@($Measure.UnknownReasons) -join ' / ')"
        }
        return @{ Spawn = $true; Reason = 'has-target'; LogLines = $lines }
    }

    if ($Measure.Unknown) {
        # P-1/P-2: 0 に見えても判定不能が混ざっていれば skip しない。必ず理由を立てる。
        $lines += "[PREFLIGHT][WARN] job=$JobName 対象0件に見えるが判定不能あり: $(@($Measure.UnknownReasons) -join ' / ') → 従来どおり起動する"
        return @{ Spawn = $true; Reason = 'preflight-unknown'; LogLines = $lines }
    }

    # P-3: 固定フォーマット。受け入れ条件がこの行をログで示すことを要求している。
    $lines += ([string]::Format($script:GissuePreflightSkipFormat, $JobName))
    $lines += "[PREFLIGHT] job=$JobName 対象0件(LLM 未起動)$detail"
    return @{ Spawn = $false; Reason = 'no-target'; LogLines = $lines }
}

# ══════════════════════════════════════════════════════════════════════════════
#  既定ポート実装（読み取りのみ・P-5/P-6）
#  判定ロジックは上の純粋関数側にしかない(片方だけ直る事故を避ける)。
#  gh/git/node の失敗(401・ネットワーク・レート制限)は必ず Unknown を返す。
#  ここで誤って Count 0 を返すと「gh が死んでいる間ずっと LLM が起動しない」になる。
# ══════════════════════════════════════════════════════════════════════════════

# 1 コールで conflict 判定(mergeable)と CI 判定(statusCheckRollup)の両方を取る。
# 返り値: @{ Ok=$true; Prs=@(...) } 相当を pscustomobject で。失敗は Ok=$false。
function Get-GissuePreflightOpenPrJson($RepoPath) {
    if (-not $RepoPath -or -not (Test-Path -LiteralPath $RepoPath)) {
        return [pscustomobject]@{ Ok = $false; Error = "パス不在: $RepoPath"; Prs = @() }
    }
    # gh に `git -C` 相当は無いので cwd を一時的に移して読み取る(読み取りのみ)。
    Push-Location -LiteralPath $RepoPath
    try {
        $raw = & gh pr list --state open --json number,mergeable,statusCheckRollup --limit 100 2>&1
        if ($LASTEXITCODE -ne 0) {
            return [pscustomobject]@{ Ok = $false; Error = "gh pr list exit=$LASTEXITCODE : $(($raw | Out-String).Trim())"; Prs = @() }
        }
        $text = ($raw | Out-String).Trim()
        if (-not $text) { return [pscustomobject]@{ Ok = $false; Error = 'gh pr list が空出力'; Prs = @() } }
        return [pscustomobject]@{ Ok = $true; Error = ''; Prs = @($text | ConvertFrom-Json) }
    } catch {
        return [pscustomobject]@{ Ok = $false; Error = "gh pr list 例外: $($_.Exception.Message)"; Prs = @() }
    } finally {
        Pop-Location
    }
}

# ── 純粋分類関数（ネットワーク不要・テストから直接 pin できる） ───────────────
# ポート実装を「取得」と「分類」に割ったのは、分類側だけを fixture で当て直せるようにするため。
# 取得側に埋め込んだままだと gh が要るので誰も当て直さず、mutant が静かに生き残る。

# [0] conflict 判定。mergeable=UNKNOWN は GitHub が計算中で「衝突なし」と断定できないため
#     Unknown に倒す（0件と読むと、計算中の衝突 PR を毎回取りこぼす）。
function Measure-GissuePreflightConflictFromPrs($Prs) {
    $hit = 0
    foreach ($p in @($Prs)) {
        if (-not $p) { continue }
        $mg = "$($p.mergeable)"
        if ($mg -eq 'UNKNOWN' -or -not $mg) {
            return New-GissuePreflightUnknown "PR #$($p.number) の mergeable が '$mg'(GitHub 計算中/不明)"
        }
        if ($mg -eq 'CONFLICTING') { $hit++ }
    }
    return New-GissuePreflightCount $hit
}

# [E] CI 失敗判定。プロンプト本文([E] 1)が FAILURE/ERROR を対象とし、2) で
#     pending/in_progress は「結果待ち」として除外すると定めている。その集合に合わせる。
$script:GissuePreflightCiFailConclusions = @('FAILURE', 'TIMED_OUT', 'CANCELLED', 'STARTUP_FAILURE', 'ACTION_REQUIRED')
$script:GissuePreflightCiFailStates      = @('FAILURE', 'ERROR')
function Measure-GissuePreflightCiFailFromPrs($Prs) {
    $hit = 0
    foreach ($p in @($Prs)) {
        if (-not $p) { continue }
        foreach ($c in @($p.statusCheckRollup)) {
            if (-not $c) { continue }
            $concl = "$($c.conclusion)".ToUpperInvariant()
            $state = "$($c.state)".ToUpperInvariant()
            if (($script:GissuePreflightCiFailConclusions -contains $concl) -or
                ($script:GissuePreflightCiFailStates -contains $state)) {
                $hit++
                break
            }
        }
    }
    return New-GissuePreflightCount $hit
}

# [F] auto-unblock stash 判定。`git stash list` の行形式は
#     "stash@{0}: On <branch>: <message>" か "stash@{0}: <message>"。
#     러너가 붙이는 접두사는 message 선두의 "auto-unblock " 뿐이다 — 어딘가에 있으면
#     된다는 식으로 느슨하게 보면 무관한 stash 를 집어 LLM 을 헛기동시킨다.
function Measure-GissuePreflightStashFromLines($Lines) {
    $hit = 0
    foreach ($l in @($Lines)) {
        if (-not $l) { continue }
        $text = "$l"
        $idx = $text.IndexOf(':')
        if ($idx -lt 0) { continue }
        $msg = $text.Substring($idx + 1).Trim()
        # "On <branch>: <message>" 形式なら branch 部分を落として message を取り出す。
        if ($msg -match '^(?:On|WIP on)\s+\S+:\s*(.*)$') { $msg = $Matches[1].Trim() }
        if ($msg.StartsWith('auto-unblock ')) { $hit++ }
    }
    return New-GissuePreflightCount $hit
}

function Get-GissuePreflightConflictingPrs($RepoPath) {
    $res = Get-GissuePreflightOpenPrJson $RepoPath
    if (-not $res.Ok) { return New-GissuePreflightUnknown $res.Error }
    return Measure-GissuePreflightConflictFromPrs $res.Prs
}

function Get-GissuePreflightFailingCiPrs($RepoPath) {
    $res = Get-GissuePreflightOpenPrJson $RepoPath
    if (-not $res.Ok) { return New-GissuePreflightUnknown $res.Error }
    return Measure-GissuePreflightCiFailFromPrs $res.Prs
}

function Get-GissuePreflightAutoUnblockStash($RepoPath) {
    if (-not $RepoPath -or -not (Test-Path -LiteralPath $RepoPath)) {
        return New-GissuePreflightUnknown "パス不在: $RepoPath"
    }
    try {
        $raw = & git -C $RepoPath stash list 2>&1
        if ($LASTEXITCODE -ne 0) {
            return New-GissuePreflightUnknown "git stash list exit=$LASTEXITCODE : $(($raw | Out-String).Trim())"
        }
        $lines = @(($raw | Out-String) -split "`r?`n" | Where-Object { $_ -and $_.Trim() })
        return Measure-GissuePreflightStashFromLines $lines
    } catch {
        return New-GissuePreflightUnknown "git stash list 例外: $($_.Exception.Message)"
    }
}

function Get-GissuePreflightRecentCommentIssues($ListIssuesScript, $Csn, $AccountsFile, $ApiBase, $HoursBack = 2) {
    if (-not $ListIssuesScript -or -not (Test-Path -LiteralPath $ListIssuesScript)) {
        return New-GissuePreflightUnknown "list-issues.js 不在: $ListIssuesScript"
    }
    # [H] は「状態無関係・直近 $HoursBack 時間にコメントが付いた issue」が対象。
    # プロンプト本文($BlockRepoMaint [H] 1.)が列挙している状態セットと同じものを渡す。
    try {
        $raw = & node $ListIssuesScript --csn $Csn --status 'PENDING,READY,IN_PROGRESS,REVIEW,TESTED,DONE' `
            --hours-back $HoursBack --accounts-file $AccountsFile --api-base $ApiBase --json 2>&1
        if ($LASTEXITCODE -ne 0) {
            return New-GissuePreflightUnknown "list-issues.js exit=$LASTEXITCODE : $(($raw | Out-String).Trim())"
        }
        $text = ($raw | Out-String).Trim()
        if (-not $text) { return New-GissuePreflightUnknown 'list-issues.js が空出力' }
        $parsed = $text | ConvertFrom-Json
        if ($null -eq $parsed) { return New-GissuePreflightCount 0 }
        return New-GissuePreflightCount (@(@($parsed) | Where-Object { $_ -and $null -ne $_.isn }).Count)
    } catch {
        return New-GissuePreflightUnknown "list-issues.js 例外: $($_.Exception.Message)"
    }
}

# 主チェックアウトだけに絞る。linked worktree は git common dir を共有するので stash/PR が
# 二重計上になる。加えて居座り worktree(giip 4804 制約: 触らない)を候補から外す効果もある。
function Select-GissuePreflightPrimaryRepos($RepoPaths) {
    $seen = @{}
    $out = @()
    foreach ($p in @($RepoPaths | Where-Object { $_ })) {
        $common = ''
        try {
            $common = (& git -C $p rev-parse --path-format=absolute --git-common-dir 2>$null | Out-String).Trim()
        } catch {}
        if (-not $common) { continue }
        $key = $common.ToLowerInvariant()
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $primary = $p
        try {
            $isLinked = (Test-Path -LiteralPath (Join-Path $p '.git') -PathType Leaf)
            if ($isLinked) {
                # common dir は <primary>/.git。その親が主チェックアウト。
                $cand = Split-Path -Parent $common
                if ($cand -and (Test-Path -LiteralPath $cand)) { $primary = $cand }
            } else {
                $top = (& git -C $p rev-parse --show-toplevel 2>$null | Out-String).Trim()
                if ($top) { $primary = $top }
            }
        } catch {}
        $out += $primary
    }
    return @($out)
}
