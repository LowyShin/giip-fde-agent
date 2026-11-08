# spawn-gate-audit.ps1 — 「LLM セッションを起動する行は、必ずゲートの内側にある」ことを
#                        **構文木(AST)で**検証する（giip 4806）
#
# なぜ必要か（先行ガードで埋まらない穴・実測）
#   giip 4804/4805 が入れた tests/test-preflight-target.ps1 / test-engine-backoff.ps1 は
#   「ゲートの呼び出しがソースに在るか」と「その文字位置が spawn より前か」を見ている。
#   これは次の 3 つを素通りする:
#     (穴1) **新しい spawn 点の追加**。別の `Start-Job`(エンジン呼び出し)や `& claude -p` を
#           増やしても、既存の pin は全部 PASS のままになる。被覆は「既に知っている 1 点」だけ。
#     (穴2) **ゲートの外へ spawn を出す改変**。ゲート呼び出しを前に残したまま spawn を
#           `if (-not $preflightDecision.Spawn) { } else { }` の**外**（後ろ）へ動かすと、
#           「ゲートが spawn より前」はそのまま成立するので通ってしまう。順序 ≠ 内包。
#     (穴3) per-issue 側の順序。先行ガードは REPO-MAINT の spawn についてだけ順序を見ており、
#           イシュー順回の `$innerJob` は「`[BACKOFF-BREAK]` という文字列が在るか」だけだった。
#   → このファイルは **spawn 点を全数列挙**し、各点が **どのゲートの内側にあるか**を
#     AST の包含関係で判定する。文字列の前後関係ではなく木の内外で見るのが要点。
#
# 処理内容 / 保存先 / 消費先（コード文書化規則）
#   - 処理: 渡されたソース文字列の構文解析と木の走査のみ。**ファイル書き込み 0 件・
#           ネットワーク 0 件・プロセス起動 0 件**（スケジューラを動かさない）。
#   - 保存先: なし（判定結果をオブジェクトで返すだけ）。
#   - 消費先: scripts/gissue/tests/test-spawn-gate-order.ps1（= run-repo-gates.ps1 が自動発見する
#             정본 게이트の一部。CI: .github/workflows/repo-gates.yml が PR / push(main) で実行）。
#             当て直し(mutation)は tests/nc-spawn-gate-order.sh。
#
# 判定契約（S-1〜S-8 — ここを崩すと「測っていないのに緑」になる）
#   S-1 構文解析が失敗したら **Ok=$false**。パースできないソースを「違反 0 件」と読まない。
#   S-2 spawn 点の定義は 2 種類だけ:
#        (a) `& claude ...` の直接起動（CommandAst の名前が literal で 'claude'）
#        (b) `Start-Job` のうち、その範囲内に `Invoke-GissueEngine` の呼び出しを含むもの
#       ヒアストリング(@"..."@)の中の同名テキストは **文字列リテラル**なので AST では
#       コマンドにならない — 文字列検索だと二重計上する所を、木で見ることで避ける。
#   S-3 spawn 点が 0 件なら **Ok=$false**。「0 件を測って違反 0 件」は通過ではない(rule 42)。
#   S-4 検出した spawn 点はすべて**レジスタ**(期待一覧)に載っていなければ違反。
#       新しい spawn 点を足したら、このレジスタに層(第1〜3層)を書くまで赤になる。
#       逆にレジスタにあるのに見つからない点も違反（当て先が消えたのを緑にしない）。
#   S-5 `Gated = 'preflight'` のレジスタ項目は、`$preflightDecision.Spawn` を条件に持つ
#       if 文の **Else 節の内側**にあること（順序ではなく内包で見る）。
#   S-6 `Gated = 'backoff-break'` のレジスタ項目は、それを囲むループの本体に
#       「`$engineBlockedThisTick` を条件に break する if 文」があり、その if が spawn より
#       **前**にあること。
#   S-7 `-DryRun` 分岐でも同じ判定が走ること。DryRun は「LLM を 1 本も起動せずにゲートの効きを
#       測る」唯一の経路なので、ここが実運転と違うと受け入れ条件そのものが測れない。
#       ※ 将来 2 か所の判定を 1 つの関数に括り出した場合は、この契約の当て先も一緒に直す
#         （括り出しは望ましいが、括り出したことを**黙って**通してはいけない）。
#   S-8 比較の大小扱いを**材料ごとに**決める（ここは先行ガードと意図的に違う）。
#       このファイルが比べるのは PowerShell の**識別子**（コマンド名・変数名・関数名・プロパティ名）
#       だけで、PowerShell はそれらを大小無視で解決する。`$preflightDecision.SPAWN` は
#       `.Spawn` と**同じプロパティ**であり、同じゲートとして動く。
#       だから識別子の比較は `OrdinalIgnoreCase` に固定する — ここを `Ordinal` にすると
#       「動きは同じなのに赤くなる」偽陽性を作り、ガードが「直す理由のない赤」を出し始める
#       （[[false-positive-breakage-needs-its-own-pin]]）。
#       逆に**契約文字列**（ログの固定書式・ラベル）を比べるときは大小を区別する。先行
#       ガード(4804/4805)がそれを担当しており、こちらでは比べない。
#
# PowerShell 5.1 互換（`??` / 三項演算子 / null 条件演算子は使わない）。

# ── レジスタ（S-4）─────────────────────────────────────────────────────────────
# Key   : 'Kind|Enclosing|Variable' の 3 点で spawn 点を同定する。行番号は使わない(動くため)。
# Layer : giip 4804 の 3 層分類。第3層(LLM 判断必須)は依頼が明示した削減対象外。
# Gated : どのゲートの内側にあるべきか。'none' は「ゲート対象外（エンジン内部の実装詳細か、
#         第3層の軽量判定）」で、その理由を Why に必ず書く。
$script:GissueSpawnSiteRegistry = @(
    @{ Key = 'engine-job|<top>|job'; Layer = 0; Gated = 'none';
       Why  = 'CSN ごとのワーカージョブ。これ自体は LLM を呼ばず、下の 2 つのゲートをこの中に持つ。' },
    @{ Key = 'engine-job|<top>|repoMaintJob'; Layer = 2; Gated = 'preflight';
       Why  = 'REPO-MAINT 세션. [0]/[E]/[F]/[H] の対象 0 件なら起動してはいけない(giip 4804)。' },
    @{ Key = 'engine-job|<top>|innerJob'; Layer = 3; Gated = 'backoff-break';
       Why  = 'per-issue セッション。対象有無は Get-GissueIssueQueue が既にプログラム判定。0 トークン即死中は残りを起動しない(giip 4805)。' },
    @{ Key = 'claude-cli|Invoke-GissueEngine|PromptText'; Layer = 3; Gated = 'none';
       Why  = 'エンジン本体の claude 起動。ここに来るのは上のゲートを通過した後だけ。' },
    @{ Key = 'claude-cli|Invoke-GissueEngine|fallbackPrompt'; Layer = 3; Gated = 'none';
       Why  = 'エンジン本体の再試行(同一セッション内のフォールバック)。新規セッションではない。' },
    @{ Key = 'claude-cli|Invoke-GissueMinimaxAttempt|PromptText'; Layer = 3; Gated = 'none';
       Why  = 'MiniMax を Anthropic 互換エンドポイントで叩く経路。claude CLI を再利用しているだけ。' },
    @{ Key = 'claude-cli|Invoke-GissueMinimaxAttempt|judgePrompt'; Layer = 3; Gated = 'none';
       Why  = 'MiniMax 出力の品質判定(haiku)。第3層=LLM 判断必須で削減対象外。' },
    @{ Key = 'claude-cli|Test-GissueCjkContamination|qaPrompt'; Layer = 3; Gated = 'none';
       Why  = 'CJK 混入 QA 判定(haiku)。第3層=LLM 判断必須で削減対象外。' }
)

# DryRun 分岐にも在るべき判定（S-7）。実運転と同一の判定関数を呼んでいることだけを見る。
$script:GissueDryRunParityAnchors = @(
    'Test-GissueBackoffActive',
    'Resolve-GissueHRecheckHoursBack',
    'Measure-GissueRepoMaintTargets',
    'Test-GissuePreflightShouldSpawn'
)

function Get-GissueSpawnGateRegistry { return @($script:GissueSpawnSiteRegistry) }

function New-GissueSpawnAuditResult($Ok, $Reason) {
    return [pscustomobject]@{
        Ok         = [bool]$Ok
        Reason     = "$Reason"
        Sites      = @()
        Violations = @()
    }
}

# 祖先をたどって「この spawn 点を囲む関数名」を得る。関数の外なら '<top>'。
function Get-GissueEnclosingFunctionName($Ast) {
    $cur = $Ast
    while ($null -ne $cur) {
        if ($cur -is [System.Management.Automation.Language.FunctionDefinitionAst]) { return "$($cur.Name)" }
        $cur = $cur.Parent
    }
    return '<top>'
}

# spawn 点を同定する 3 点目(= 行番号を使わない安定キー)を得る。
#   優先 1: その起動へ**流し込んでいる**変数。`$fallbackPrompt | & claude -p ...` の fallbackPrompt。
#           エンジン内に 2 本ある claude 起動(本命/再試行)を区別できる唯一の安定材料がこれ。
#   優先 2: 代入先の変数。`$innerJob = Start-Job ...` の innerJob。
# ⚠ 祖先の走査は **関数/スクリプトブロックの境界で止める**。止めないと、関数の中の起動が
#   外側の `$job = Start-Job ...` まで登っていき、別々の起動点が同じキー('job')に潰れる
#   (実測: Invoke-GissueEngine の 2 本が両方 'job' になった)。
function Get-GissueSpawnTargetVariable($Ast) {
    $parent = $Ast.Parent
    if ($parent -is [System.Management.Automation.Language.PipelineAst]) {
        $els = @($parent.PipelineElements)
        if ($els.Count -gt 1 -and $els[0].Extent.StartOffset -lt $Ast.Extent.StartOffset) {
            $first = $els[0]
            if ($first -is [System.Management.Automation.Language.CommandExpressionAst] -and
                $first.Expression -is [System.Management.Automation.Language.VariableExpressionAst]) {
                return "$($first.Expression.VariablePath.UserPath)"
            }
        }
    }
    $cur = $Ast
    while ($null -ne $cur) {
        if ($cur -is [System.Management.Automation.Language.AssignmentStatementAst]) {
            $lhs = $cur.Left
            if ($lhs -is [System.Management.Automation.Language.VariableExpressionAst]) {
                return "$($lhs.VariablePath.UserPath)"
            }
            return '<assign>'
        }
        if ($cur -is [System.Management.Automation.Language.FunctionDefinitionAst]) { break }
        $cur = $cur.Parent
    }
    return '<none>'
}

# `& claude -p` の直接起動（S-2a）。コマンド名が literal で 'claude' のものだけ。
function Get-GissueClaudeCliSites($RootAst) {
    $out = @()
    $cmds = @($RootAst.FindAll({ param($a) $a -is [System.Management.Automation.Language.CommandAst] }, $true))
    foreach ($c in $cmds) {
        $name = $c.GetCommandName()
        if ($null -eq $name) { continue }
        # S-8: 識別子なので大小は無視する。`& Claude -p` も PowerShell は同じ claude を起動する。
        if (-not [string]::Equals("$name", 'claude', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $out += [pscustomobject]@{
            Kind      = 'claude-cli'
            Enclosing = (Get-GissueEnclosingFunctionName $c)
            Variable  = (Get-GissueSpawnTargetVariable $c)
            Offset    = $c.Extent.StartOffset
            Line      = $c.Extent.StartLineNumber
            Ast       = $c
        }
    }
    return @($out)
}

# エンジンを起動する `Start-Job`（S-2b）。範囲内に Invoke-GissueEngine の呼び出しを含むもの。
function Get-GissueEngineJobSites($RootAst) {
    $out = @()
    $cmds = @($RootAst.FindAll({ param($a) $a -is [System.Management.Automation.Language.CommandAst] }, $true))
    foreach ($c in $cmds) {
        $name = $c.GetCommandName()
        if ($null -eq $name) { continue }
        if (-not [string]::Equals("$name", 'Start-Job', [System.StringComparison]::OrdinalIgnoreCase)) { continue }
        $inner = @($c.FindAll({ param($a)
            if (-not ($a -is [System.Management.Automation.Language.CommandAst])) { return $false }
            $n = $a.GetCommandName()
            if ($null -eq $n) { return $false }
            return [string]::Equals("$n", 'Invoke-GissueEngine', [System.StringComparison]::OrdinalIgnoreCase)
        }, $true))
        if ($inner.Count -eq 0) { continue }
        $out += [pscustomobject]@{
            Kind      = 'engine-job'
            Enclosing = (Get-GissueEnclosingFunctionName $c)
            Variable  = (Get-GissueSpawnTargetVariable $c)
            Offset    = $c.Extent.StartOffset
            Line      = $c.Extent.StartLineNumber
            Ast       = $c
        }
    }
    return @($out)
}

# S-5: `$preflightDecision.Spawn` を条件に持つ if 文の Else 節の内側にあるか（内包で見る）。
function Test-GissueSiteInsidePreflightElse($Site) {
    $cur = $Site.Ast
    while ($null -ne $cur) {
        $parent = $cur.Parent
        if ($parent -is [System.Management.Automation.Language.IfStatementAst]) {
            $condText = ''
            foreach ($cl in $parent.Clauses) { $condText = $condText + "$($cl.Item1.Extent.Text)" }
            if ($condText.IndexOf('$preflightDecision.Spawn', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                if ($null -ne $parent.ElseClause) {
                    $eo = $parent.ElseClause.Extent.StartOffset
                    $ec = $parent.ElseClause.Extent.EndOffset
                    if ($Site.Offset -ge $eo -and $Site.Offset -lt $ec) { return $true }
                }
            }
        }
        $cur = $parent
    }
    return $false
}

# S-6: 囲むループの本体に「$engineBlockedThisTick で break する if」があり、spawn より前か。
function Test-GissueSiteGuardedByBackoffBreak($Site) {
    $cur = $Site.Ast
    while ($null -ne $cur) {
        $isLoop = ($cur -is [System.Management.Automation.Language.ForStatementAst]) -or
                  ($cur -is [System.Management.Automation.Language.ForEachStatementAst]) -or
                  ($cur -is [System.Management.Automation.Language.WhileStatementAst])
        if ($isLoop) {
            $ifs = @($cur.FindAll({ param($a) $a -is [System.Management.Automation.Language.IfStatementAst] }, $true))
            foreach ($if in $ifs) {
                $condText = ''
                foreach ($cl in $if.Clauses) { $condText = $condText + "$($cl.Item1.Extent.Text)" }
                if ($condText.IndexOf('$engineBlockedThisTick', [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
                $breaks = @($if.FindAll({ param($a) $a -is [System.Management.Automation.Language.BreakStatementAst] }, $true))
                if ($breaks.Count -eq 0) { continue }
                if ($if.Extent.StartOffset -lt $Site.Offset) { return $true }
            }
        }
        $cur = $cur.Parent
    }
    return $false
}

# S-7: `-DryRun` 分岐の内側に、実運転と同じ判定関数の呼び出しが在るか。
function Get-GissueDryRunParityViolations($RootAst) {
    $v = @()
    $ifs = @($RootAst.FindAll({ param($a) $a -is [System.Management.Automation.Language.IfStatementAst] }, $true))
    $dryBlocks = @()
    foreach ($if in $ifs) {
        foreach ($cl in $if.Clauses) {
            $condText = "$($cl.Item1.Extent.Text)"
            # 条件が `$DryRun` そのもの(否定でない)の分岐だけを見る。`-not $DryRun` は実運転側。
            if (($condText.IndexOf('$DryRun', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -and
                ($condText.IndexOf('-not', [System.StringComparison]::OrdinalIgnoreCase) -lt 0)) {
                $dryBlocks += $cl.Item2
            }
        }
    }
    if ($dryBlocks.Count -eq 0) {
        $v += 'S-7: `-DryRun` 分岐が見つからない — DryRun はゲートの効きを LLM 無しで測る唯一の経路なので、消えたら測定不能'
        return @($v)
    }
    foreach ($anchor in @($script:GissueDryRunParityAnchors)) {
        $found = $false
        foreach ($b in $dryBlocks) {
            $calls = @($b.FindAll({ param($a) $a -is [System.Management.Automation.Language.CommandAst] }, $true))
            foreach ($c in $calls) {
                $n = $c.GetCommandName()
                if ($null -eq $n) { continue }
                if ([string]::Equals("$n", $anchor, [System.StringComparison]::OrdinalIgnoreCase)) { $found = $true; break }
            }
            if ($found) { break }
        }
        if (-not $found) {
            $v += "S-7: `-DryRun` 分岐が '$anchor' を呼んでいない — DryRun の出力が実運転と食い違う(対象0件でも「起動予定」と報告する)"
        }
    }
    return @($v)
}

# ── 本体 ───────────────────────────────────────────────────────────────────────
# $RegistryOverride を渡せるのは**テスト用**(fixture で「ゲートの外に出した版」を測るため)。
# 省略時は正本レジスタを使う — 本番の判定材料が 2 系統に分かれないようにする(rule 48)。
# ⚠ パラメータ名を `$Registry` にしてはいけない。PowerShell の変数名は**大小を区別しない**ので、
#   本体のローカル `$registry = @(...)` が**同じ変数**を上書きし、渡した fixture が黙って
#   無視される(実測: テスト 5 件が正本レジスタで判定され、原因が見えないまま赤くなった)。
function Get-GissueSpawnGateAudit([string]$Source, [string]$SourcePath = '(inline)', $RegistryOverride = $null) {
    if ($null -eq $Source -or -not "$Source".Trim()) {
        return (New-GissueSpawnAuditResult $false "ソースが空: $SourcePath")
    }
    $tokens = $null
    $errors = $null
    $rootAst = $null
    try {
        $rootAst = [System.Management.Automation.Language.Parser]::ParseInput($Source, [ref]$tokens, [ref]$errors)
    } catch {
        return (New-GissueSpawnAuditResult $false "構文解析が例外: $($_.Exception.Message)")
    }
    # S-1
    if ($null -eq $rootAst) { return (New-GissueSpawnAuditResult $false '構文解析が null を返した') }
    if ($null -ne $errors -and @($errors).Count -gt 0) {
        return (New-GissueSpawnAuditResult $false "構文エラー $(@($errors).Count) 件: $(@($errors)[0].Message)")
    }

    $sites = @()
    $sites += (Get-GissueClaudeCliSites $rootAst)
    $sites += (Get-GissueEngineJobSites $rootAst)
    $sites = @($sites | Sort-Object Offset)

    $res = [pscustomobject]@{
        Ok         = $true
        Reason     = ''
        Sites      = @()
        Violations = @()
    }

    # S-3
    if ($sites.Count -eq 0) {
        $res.Ok = $false
        $res.Reason = 'LLM 起動点が 0 件 — 検査器が何も検査していない(rule 42)。当て先が消えた可能性を疑う'
        return $res
    }

    $registry = @($script:GissueSpawnSiteRegistry)
    if ($null -ne $RegistryOverride) { $registry = @($RegistryOverride) }
    $seenKeys = @()
    $siteRows = @()
    $violations = @()

    foreach ($s in $sites) {
        $key = "$($s.Kind)|$($s.Enclosing)|$($s.Variable)"
        $seenKeys += $key
        $entry = $null
        foreach ($r in $registry) {
            if ([string]::Equals("$($r.Key)", $key, [System.StringComparison]::OrdinalIgnoreCase)) { $entry = $r; break }
        }
        if ($null -eq $entry) {
            # S-4: レジスタに無い spawn 点 = 「誰も層を決めていない LLM 起動」。
            $violations += "S-4: 未登録の LLM 起動点 key='$key' (line $($s.Line)) — レジスタに層とゲートを書くまで通さない"
            $siteRows += [pscustomobject]@{ Key = $key; Line = $s.Line; Gated = '(未登録)'; Pass = $false }
            continue
        }
        $pass = $true
        if ([string]::Equals("$($entry.Gated)", 'preflight', [System.StringComparison]::Ordinal)) {
            if (-not (Test-GissueSiteInsidePreflightElse $s)) {
                $violations += "S-5: '$key' (line $($s.Line)) がプリフライト判定の内側に無い — ゲート呼び出しが前に在っても、spawn が分岐の外なら素通りする"
                $pass = $false
            }
        } elseif ([string]::Equals("$($entry.Gated)", 'backoff-break', [System.StringComparison]::Ordinal)) {
            if (-not (Test-GissueSiteGuardedByBackoffBreak $s)) {
                $violations += "S-6: '$key' (line $($s.Line)) を囲むループに `$engineBlockedThisTick で break する判定が spawn より前に無い"
                $pass = $false
            }
        }
        $siteRows += [pscustomobject]@{ Key = $key; Line = $s.Line; Gated = "$($entry.Gated)"; Pass = $pass }
    }

    # S-4 の裏側: レジスタにあるのに見つからない点
    foreach ($r in $registry) {
        $hit = $false
        foreach ($k in $seenKeys) {
            if ([string]::Equals("$($r.Key)", "$k", [System.StringComparison]::OrdinalIgnoreCase)) { $hit = $true; break }
        }
        if (-not $hit) {
            $violations += "S-4: レジスタの '$($r.Key)' が見つからない — 当て先が消えたのを「違反 0 件」と読まない"
        }
    }

    # S-7
    $violations += (Get-GissueDryRunParityViolations $rootAst)

    $res.Sites = @($siteRows)
    $res.Violations = @($violations | Where-Object { $_ })
    $res.Ok = (@($res.Violations).Count -eq 0)
    if (-not $res.Ok) { $res.Reason = "違反 $(@($res.Violations).Count) 件" }
    return $res
}

# ファイル版。読めなければ Ok=$false（S-1 と同じ理由で、不在を緑にしない）。
function Get-GissueSpawnGateAuditForFile([string]$Path, $RegistryOverride = $null) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return (New-GissueSpawnAuditResult $false "検査対象が見つからない: $Path")
    }
    $src = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    return (Get-GissueSpawnGateAudit $src $Path $RegistryOverride)
}
