# engine-backoff.ps1 — エンジン(claude/MiniMax)の「0トークン即死」を検知して再起動を止める（giip 4805）
#
# 用途
#   run-gissue-claude.ps1 は 20 分ごと(cron `7,27,47`)に起動し、REPO-MAINT 1 本 + キュー上の
#   イシュー全件に対して `claude -p` を spawn する。アカウントが上限到達・未ログインのときは
#   その spawn が**何もせず即死**するが、러너はそれを一切見ていなかった。実測(giip-4804
#   ベースライン: smartorder-works/.agent/metrics/scheduler-baseline-giip-4804.md)では
#   **3,709 セッション中 1,338 本(36.1%)が 0 トークン即死**し、LIMIT_WEEKLY 1,080 /
#   NOT_LOGGED_IN 248 がその理由だった。ログにはこう残っていた:
#
#       [ISSUE] isn=4404 status=STALE_IN_PROGRESS ... 처리 시작
#       [RUN-COUNTS] processed=1
#       You've hit your weekly limit · resets 9pm (UTC)
#       [ISSUE] isn=4402 status=READY ... 처리 시작        ← 同じティック内で次を spawn
#       [RUN-COUNTS] processed=2
#       You've hit your weekly limit · resets 9pm (UTC)
#
#   つまり「1 ティックでキュー全件を空振りさせ、20 分後にまた全件空振りさせる」構造だった。
#   このファイルはその 2 つ(ティック内の続行・ティック間の再起動)を両方止める。
#
# 処理内容 / 保存先 / 消費先（コード文書化規則: 用途・処理・保存・消費を具体的に）
#   - 処理: エンジン出力テキストの分類(純粋関数) → バックオフ期限の決定(純粋関数) →
#           状態ファイルの読み書き。**ネットワーク呼び出しは 0 件**。
#   - 保存先: `<logDir>/engine_backoff_state.json`（1 ファイル・JSON。スキーマは下記 S-1）。
#   - 消費先: run-gissue-claude.ps1 の
#             (1) per-CSN ジョブ入口のティックゲート（REPO-MAINT と イシュー順回の両方を止める）
#             (2) イシュー順回の各周回先頭（ティック内で以降の spawn を止める）
#             (3) REPO-MAINT / per-issue のジョブ出力受領直後（検知して状態に書く）
#             (4) Phase 2 の PrGateSweep / ReviewDoneAudit（claude-haiku 判定を呼ぶ 2 つ）
#             tests/test-engine-backoff.ps1（純粋関数を実文面で pin）。
#
# 判定契約（B-1〜B-8 — ここを崩すと「静かに全停止」か「空振り継続」のどちらかに倒れる）
#   B-1 分類の needle は **実測された文面**だけを根拠にする。2026-10〜11 の実測は 5 種:
#         You've hit your monthly spend limit · raise it at … · your weekly limit resets Oct 26, 9pm (UTC)
#         You've hit your weekly limit · resets Nov 2, 9pm (UTC)
#         You've hit your weekly limit · resets 9pm (UTC)
#         You've hit your session limit · resets 3:50pm (UTC)
#         Not logged in · Please run /login
#       未知文面は `LIMIT_OTHER`(`hit your … limit` の総称)に落として件数を残す。勝手に既知へ寄せない。
#   B-2 **文字列がどこかに在るだけでは即死と判定しない**（[[substring-anywhere-is-not-an-anchor]]）。
#       このスケジューラは**自分自身についてのイシューを処理する**(本タスク giip-4805 がまさにそれ)。
#       イシュー本文やエンジンの正常出力に "You've hit your weekly limit" が引用されるだけで
#       バックオフが立つと、**働いているのに全停止する**。そこで
#         (a) 判定は blob 全体ではなく **行単位**で、観測文面は行頭アンカー(`^`)で当てる
#         (b) 러너自身が出す `[LABEL]` 行を除いた **実質出力行が $MaxDeathLines(既定3)以下**のときだけ
#             Blocked とする。実測の即死は常に 1 行だった。実際に働いたセッションは必ずそれより長い。
#   B-3 リセット時刻は文面から取る(`resets Nov 2, 9pm (UTC)` / `resets 3:50pm (UTC)`)。
#       年は文面に無いので「現在から ±180 日に最も近い年」を採る。
#   B-4 **LIMIT_MONTHLY は文面のリセット時刻を使わない**。実測文面は
#       「monthly spend limit に当たった」と言いながら添えてあるのは *weekly* limit のリセット時刻で、
#       **別の窓**である。それを月次の復帰時刻として使うと、週次リセットごとに起きて即死し直す。
#       よって月次は指数バックオフ(上限 12h)にし、復帰は人の操作(上限引き上げ)を前提にする。
#   B-5 状態ファイルが読めない/壊れているときは **バックオフなし(=従来どおり起動)** に倒し、
#       必ず `[BACKOFF][WARN]` を残す。理由: 読めないファイルで全処理を止めるほうが害が大きく、
#       かつ起動すれば即死してこのファイルが正しい内容で書き直される(自己修復する)。
#       ただし黙って通さない — 警告を出さずに通す経路は作らない。
#   B-6 ログ行は固定フォーマット `BACKOFF reason=<kind> until=<ISO8601>`（タスクの受け入れ条件が
#       この行を要求しているため、文字列は契約であって自由書式ではない）。
#   B-7 実際に動いたセッション(= Blocked でなく実質出力がある)の直後は状態をクリアする。
#       クリアしないと一度上限に当たったあと復帰しても連続カウントが残り、過剰に待つ。
#   B-8 ゲート判定はファイル読み取りだけ(ネットワーク 0)。ティックごとに何度呼んでも安い。
#
#   S-1 状態ファイルのスキーマ:
#       { kind, until(ISO8601 UTC), consecutive(int), detectedAt(ISO8601 UTC), source, detail, job }
#
# PowerShell 5.1 互換(`??` / 三項演算子 / null 条件演算子は使わない — 5.1 パーサが
# ファイル全体を落とすため。scripts/gissue/check-ps1-parse.ps1 がこれを検査する)。

$script:GissueBackoffLogFormat = 'BACKOFF reason={0} until={1}'
# 実質出力行がこの数以下のときだけ「即死」と見なす(B-2 b)。実測の即死は 1 行。
$script:GissueBackoffMaxDeathLines = 3
# 러너自身が出すマーカー行(`[ISSUE]` `[ENGINE]` `[WARN]` `[RUN-COUNTS]` …)。実質出力から除く。
$script:GissueBackoffRunnerLinePattern = '^\[[A-Z0-9][A-Z0-9_\-]*\]'
# 指数バックオフの基準(分)。cron 間隔(20分)と同じ — 1 段目で必ず 1 ティック以上空ける。
$script:GissueBackoffBaseMinutes = 20
# 種別ごとの上限(分)。復帰に人の操作が要るものは長く、一時的なものは短く。
$script:GissueBackoffCapMinutes = @{
    'LIMIT_SESSION'  = 60
    'LIMIT_WEEKLY'   = 360
    'LIMIT_MONTHLY'  = 720
    'LIMIT_OTHER'    = 360
    'NOT_LOGGED_IN'  = 360
    'OVERLOADED'     = 30
}
# 文面にリセット時刻が添えられていても**使わない**種別(B-4)。
$script:GissueBackoffIgnoreResetKinds = @('LIMIT_MONTHLY', 'NOT_LOGGED_IN', 'OVERLOADED')

# 分類表(B-1)。LinePattern は **行単位**で当てる。順序は「具体 → 総称」。
#   Anchored=$true  … 実測文面。行頭から当てる(引用を拾わない)。
#   Anchored=$false … API 由来のエラー文面。行中含有で当てる(行頭が定型でない)。
$script:GissueBackoffPatterns = @(
    @{ Kind = 'LIMIT_MONTHLY'; Anchored = $true;  LinePattern = "^\s*You've hit your monthly" },
    @{ Kind = 'LIMIT_WEEKLY';  Anchored = $true;  LinePattern = "^\s*You've hit your weekly limit" },
    @{ Kind = 'LIMIT_SESSION'; Anchored = $true;  LinePattern = "^\s*You've hit your session limit" },
    @{ Kind = 'NOT_LOGGED_IN'; Anchored = $true;  LinePattern = '^\s*Not logged in' },
    # 総称: 既知の 3 窓に当たらない `hit your <何か> limit`(例: 将来の 5-hour limit)。
    @{ Kind = 'LIMIT_OTHER';   Anchored = $true;  LinePattern = "^\s*You've hit your .{0,32}limit" },
    @{ Kind = 'LIMIT_SESSION'; Anchored = $false; LinePattern = 'usage limit reached' },
    @{ Kind = 'NOT_LOGGED_IN'; Anchored = $false; LinePattern = '(?:invalid api key|please run /login|authentication_error|credit balance is too low|oauth token (?:has )?expired)' },
    @{ Kind = 'OVERLOADED';    Anchored = $false; LinePattern = 'overloaded' }
)

# ── 純粋関数: 実質出力行の抽出（B-2 b） ─────────────────────────────────────────
function Get-GissueBackoffMeaningfulLines($Text) {
    $out = @()
    if ($null -eq $Text) { return $out }
    $blob = ''
    if ($Text -is [string]) { $blob = $Text } else { $blob = (@($Text) | Out-String) }
    foreach ($raw in ($blob -split "`r?`n")) {
        $t = "$raw".Trim()
        if (-not $t) { continue }
        if ($t -cmatch $script:GissueBackoffRunnerLinePattern) { continue }
        $out += $t
    }
    return $out
}

# ── 純粋関数: 即死の分類（B-1/B-2） ───────────────────────────────────────────
# 返り値: @{ Blocked; Kind; ResetRaw; Evidence; MeaningfulLines }
function Get-GissueEngineBlockKind($Text, [int]$MaxDeathLines = 0) {
    $cap = $MaxDeathLines
    if ($cap -le 0) { $cap = $script:GissueBackoffMaxDeathLines }
    $lines = @(Get-GissueBackoffMeaningfulLines $Text)
    $result = [pscustomobject]@{
        Blocked         = $false
        Kind            = ''
        ResetRaw        = ''
        Evidence        = ''
        MeaningfulLines = $lines.Count
        Reason          = ''
    }
    $hitKind = ''
    $hitLine = ''
    foreach ($line in $lines) {
        foreach ($p in $script:GissueBackoffPatterns) {
            $m = $false
            if ($p.Anchored) { $m = ($line -cmatch $p.LinePattern) } else { $m = ($line -match $p.LinePattern) }
            if ($m) { $hitKind = $p.Kind; $hitLine = $line; break }
        }
        if ($hitKind) { break }
    }
    if (-not $hitKind) {
        $result.Reason = 'no-match'
        return $result
    }
    # B-2 b: 文面に当たっても、実質出力が長ければ「働いたセッションが言及しただけ」。止めない。
    if ($lines.Count -gt $cap) {
        $result.Kind = $hitKind
        $result.Evidence = $hitLine
        $result.Reason = "mention-only(実質出力 $($lines.Count) 行 > 上限 $cap 行 — 即死ではない)"
        return $result
    }
    $result.Blocked = $true
    $result.Kind = $hitKind
    $result.Evidence = $hitLine
    $result.Reason = 'death'
    # `resets Nov 2, 9pm (UTC)` / `resets 3:50pm (UTC)` の右辺を素のまま持つ(解釈は次の関数)。
    if ($hitLine -match 'resets\s+(.+?)(?:\s*\(UTC\))?\s*$') { $result.ResetRaw = $Matches[1].Trim() }
    return $result
}

# ── 純粋関数: 文面のリセット時刻 → UTC DateTime（B-3） ───────────────────────────
# 返り値: @{ Ok; Until; Reason }
function ConvertTo-GissueResetUtc([string]$ResetRaw, [datetime]$NowUtc) {
    $res = @{ Ok = $false; Until = $NowUtc; Reason = '' }
    if (-not $ResetRaw) { $res.Reason = 'リセット時刻の記載なし'; return $res }
    $txt = $ResetRaw.Trim()
    $mon = 0; $day = 0; $hour = -1; $minute = 0; $ampm = ''
    # 形式1: "Nov 2, 9pm" / "Oct 26, 9:30pm"
    if ($txt -match '^([A-Za-z]{3,9})\s+(\d{1,2}),\s*(\d{1,2})(?::(\d{2}))?\s*([AaPp])[Mm]$') {
        $monName = $Matches[1].Substring(0, 3).ToLowerInvariant()
        $names = @('jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec')
        $mon = ([array]::IndexOf($names, $monName)) + 1
        if ($mon -le 0) { $res.Reason = "月名を解釈できない: $txt"; return $res }
        $day = [int]$Matches[2]
        $hour = [int]$Matches[3]
        if ($Matches[4]) { $minute = [int]$Matches[4] }
        $ampm = $Matches[5].ToLowerInvariant()
    # 形式2: "9pm" / "3:50pm"（日付なし = 直近の該当時刻）
    } elseif ($txt -match '^(\d{1,2})(?::(\d{2}))?\s*([AaPp])[Mm]$') {
        $hour = [int]$Matches[1]
        if ($Matches[2]) { $minute = [int]$Matches[2] }
        $ampm = $Matches[3].ToLowerInvariant()
    } else {
        $res.Reason = "リセット時刻の形式が未知: $txt"
        return $res
    }
    if ($hour -lt 1 -or $hour -gt 12) { $res.Reason = "時が範囲外: $txt"; return $res }
    if ($minute -lt 0 -or $minute -gt 59) { $res.Reason = "分が範囲外: $txt"; return $res }
    $h24 = $hour
    if ($ampm -eq 'p') { if ($hour -lt 12) { $h24 = $hour + 12 } } else { if ($hour -eq 12) { $h24 = 0 } }

    if ($mon -gt 0) {
        # B-3: 年が文面に無い。現在から ±180 日に最も近い年を採る。
        $best = $null
        foreach ($yOff in @(0, 1, -1)) {
            $y = $NowUtc.Year + $yOff
            $cand = $null
            try { $cand = [datetime]::new($y, $mon, $day, $h24, $minute, 0, [System.DateTimeKind]::Utc) } catch { continue }
            if ($null -eq $best) { $best = $cand; continue }
            if ([math]::Abs(($cand - $NowUtc).TotalDays) -lt [math]::Abs(($best - $NowUtc).TotalDays)) { $best = $cand }
        }
        if ($null -eq $best) { $res.Reason = "日付を構成できない: $txt"; return $res }
        $res.Ok = $true
        $res.Until = $best
        return $res
    }
    # 日付なし: 今日のその時刻。すでに過ぎていれば翌日。
    $today = [datetime]::new($NowUtc.Year, $NowUtc.Month, $NowUtc.Day, $h24, $minute, 0, [System.DateTimeKind]::Utc)
    if ($today -le $NowUtc) { $today = $today.AddDays(1) }
    $res.Ok = $true
    $res.Until = $today
    return $res
}

# ── 純粋関数: 指数バックオフ（B-4） ─────────────────────────────────────────────
function Get-GissueBackoffDelayMinutes([string]$Kind, [int]$Consecutive) {
    $n = $Consecutive
    if ($n -lt 1) { $n = 1 }
    if ($n -gt 16) { $n = 16 }   # [math]::Pow の暴走と桁あふれを防ぐ(上限で頭打ちになるので実害なし)
    $cap = 360
    if ($script:GissueBackoffCapMinutes.ContainsKey($Kind)) { $cap = [int]$script:GissueBackoffCapMinutes[$Kind] }
    $delay = [int]($script:GissueBackoffBaseMinutes * [math]::Pow(2, ($n - 1)))
    if ($delay -gt $cap) { $delay = $cap }
    return $delay
}

# ── 純粋関数: 期限の決定（B-3/B-4 の合流点） ─────────────────────────────────────
# 返り値: @{ Until; Source('reset-time'|'exponential'); Note }
function Resolve-GissueBackoffUntil([string]$Kind, [string]$ResetRaw, [int]$Consecutive, [datetime]$NowUtc) {
    $useReset = -not ($script:GissueBackoffIgnoreResetKinds -contains $Kind)
    if ($useReset) {
        $p = ConvertTo-GissueResetUtc $ResetRaw $NowUtc
        if ($p.Ok) {
            if ($p.Until -gt $NowUtc) {
                # リセット直後に当てて再度即死しないよう 2 分の余裕を足す。
                return @{ Until = $p.Until.AddMinutes(2); Source = 'reset-time'; Note = "文面のリセット時刻 '$ResetRaw' を採用" }
            }
            $d0 = Get-GissueBackoffDelayMinutes $Kind $Consecutive
            return @{ Until = $NowUtc.AddMinutes($d0); Source = 'exponential'; Note = "文面のリセット時刻 '$ResetRaw' が現在以前(時刻ずれ/古い出力) — 指数 ${d0}分に倒す" }
        }
        $d1 = Get-GissueBackoffDelayMinutes $Kind $Consecutive
        return @{ Until = $NowUtc.AddMinutes($d1); Source = 'exponential'; Note = "$($p.Reason) — 指数 ${d1}分" }
    }
    $d = Get-GissueBackoffDelayMinutes $Kind $Consecutive
    $note = "種別 $Kind は文面のリセット時刻を使わない — 指数 ${d}分"
    if ($Kind -eq 'LIMIT_MONTHLY' -and $ResetRaw) {
        # B-4: 月次に当たったのに添えてあるのは *weekly* のリセット時刻。別の窓なので使わない。
        $note = "LIMIT_MONTHLY: 文面の 'resets $ResetRaw' は weekly 窓のリセットで月次の復帰時刻ではない — 指数 ${d}分(復帰には上限引き上げが必要)"
    }
    return @{ Until = $NowUtc.AddMinutes($d); Source = 'exponential'; Note = $note }
}

# ══════════════════════════════════════════════════════════════════════════════
#  状態ファイル（S-1 / B-5 / B-8）
# ══════════════════════════════════════════════════════════════════════════════

function Get-GissueBackoffStatePath($LogDir) {
    return (Join-Path $LogDir 'engine_backoff_state.json')
}

# 読めない/壊れているときは $null を返す(= バックオフなしに倒す。B-5)。
# Reason を第2戻り値として返さず、Ok を持つオブジェクトで返す — 「無い」と「読めない」を
# 呼び出し側が区別して WARN を出せるようにする(黙って通す経路を作らない)。
function Read-GissueBackoffState($StateFile) {
    if (-not $StateFile) { return [pscustomobject]@{ Ok = $false; State = $null; Error = '状態ファイルのパスが未指定' } }
    if (-not (Test-Path -LiteralPath $StateFile)) { return [pscustomobject]@{ Ok = $true; State = $null; Error = '' } }
    try {
        $raw = Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8
        if (-not "$raw".Trim()) { return [pscustomobject]@{ Ok = $true; State = $null; Error = '' } }
        $obj = $raw | ConvertFrom-Json
        if ($null -eq $obj -or -not $obj.until) {
            return [pscustomobject]@{ Ok = $false; State = $null; Error = '状態ファイルに until が無い' }
        }
        return [pscustomobject]@{ Ok = $true; State = $obj; Error = '' }
    } catch {
        return [pscustomobject]@{ Ok = $false; State = $null; Error = "状態ファイル読み取り失敗: $($_.Exception.Message)" }
    }
}

function Write-GissueBackoffState($StateFile, $State) {
    try {
        ($State | ConvertTo-Json -Depth 4) | Out-File -FilePath $StateFile -Encoding UTF8
        return $true
    } catch {
        return $false
    }
}

function Clear-GissueBackoffState($StateFile) {
    try {
        if ($StateFile -and (Test-Path -LiteralPath $StateFile)) { Remove-Item -LiteralPath $StateFile -Force -ErrorAction Stop }
        return $true
    } catch {
        return $false
    }
}

# ティックゲート。返り値: @{ Active; Kind; Until; LogLines }
function Test-GissueBackoffActive($StateFile, [datetime]$NowUtc, $JobLabel = '') {
    $r = Read-GissueBackoffState $StateFile
    if (-not $r.Ok) {
        # B-5: 読めないときは止めない。ただし黙って通さない。
        return @{ Active = $false; Kind = ''; Until = $null; LogLines = @("[BACKOFF][WARN] $($r.Error) — バックオフなしとして従来どおり起動する(起動すれば即死時に状態が書き直される)") }
    }
    if ($null -eq $r.State) { return @{ Active = $false; Kind = ''; Until = $null; LogLines = @() } }
    $until = $null
    try {
        $until = [datetime]::Parse("$($r.State.until)", [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
    } catch {
        return @{ Active = $false; Kind = ''; Until = $null; LogLines = @("[BACKOFF][WARN] until='$($r.State.until)' を日時として解釈できない — バックオフなしとして従来どおり起動する") }
    }
    $kind = "$($r.State.kind)"
    if (-not $kind) { $kind = 'UNKNOWN' }
    if ($until -le $NowUtc) {
        return @{ Active = $false; Kind = $kind; Until = $until; LogLines = @("[BACKOFF] 期限切れ(reason=$kind until=$($until.ToString('o'))) — 通常どおり起動する") }
    }
    $lines = @()
    # B-6: 固定フォーマット。受け入れ条件がこの行をログで示すことを要求している。
    $lines += ([string]::Format($script:GissueBackoffLogFormat, $kind, $until.ToString('o')))
    $label = ''
    if ($JobLabel) { $label = " job=$JobLabel" }
    $waitMin = [int][math]::Ceiling(($until - $NowUtc).TotalMinutes)
    $lines += "[BACKOFF] LLM 未起動$label — 残り ${waitMin}分(consecutive=$($r.State.consecutive) source=$($r.State.source) detail=$($r.State.detail))"
    return @{ Active = $true; Kind = $kind; Until = $until; LogLines = $lines }
}

# エンジン出力を見て、即死なら状態に書く。返り値: @{ Blocked; Kind; Until; LogLines }
# 働いたセッション(= Blocked でない & 実質出力あり)なら状態をクリアする(B-7)。
function Set-GissueBackoffFromOutput($StateFile, $OutputText, [datetime]$NowUtc, $JobLabel = '') {
    $cls = Get-GissueEngineBlockKind $OutputText
    $label = ''
    if ($JobLabel) { $label = " job=$JobLabel" }
    if (-not $cls.Blocked) {
        $lines = @()
        if ($cls.Kind) {
            # 文面には当たったが実質出力が長い = 言及しただけ。止めないことを明示的に残す(B-2)。
            $lines += "[BACKOFF] 上限文面に一致したが $($cls.Reason)$label — バックオフしない"
        }
        if ($cls.MeaningfulLines -gt 0) {
            $prev = Read-GissueBackoffState $StateFile
            if ($prev.Ok -and $null -ne $prev.State) {
                if (Clear-GissueBackoffState $StateFile) {
                    $lines += "[BACKOFF] 解除 — エンジンが実際に出力した(実質 $($cls.MeaningfulLines) 行)$label"
                }
            }
        }
        return @{ Blocked = $false; Kind = $cls.Kind; Until = $null; LogLines = $lines }
    }
    $consecutive = 1
    $prevState = Read-GissueBackoffState $StateFile
    if ($prevState.Ok -and $null -ne $prevState.State) {
        $pk = "$($prevState.State.kind)"
        $pc = 0
        try { $pc = [int]$prevState.State.consecutive } catch { $pc = 0 }
        # 同じ種別が続いているときだけ積む。別種別は 1 から数え直す(窓が違うので待ち時間も違う)。
        if ($pk -eq $cls.Kind -and $pc -gt 0) { $consecutive = $pc + 1 }
    }
    $resolved = Resolve-GissueBackoffUntil $cls.Kind $cls.ResetRaw $consecutive $NowUtc
    $state = [pscustomobject]@{
        kind        = $cls.Kind
        until       = $resolved.Until.ToString('o')
        consecutive = $consecutive
        detectedAt  = $NowUtc.ToString('o')
        source      = $resolved.Source
        detail      = $cls.Evidence
        job         = "$JobLabel"
    }
    $lines = @()
    $lines += "[BACKOFF] 0 토큰 즉사 검지$label — kind=$($cls.Kind) consecutive=$consecutive / $($resolved.Note)"
    $lines += "[BACKOFF] evidence: $($cls.Evidence)"
    # B-6: 固定フォーマット。
    $lines += ([string]::Format($script:GissueBackoffLogFormat, $cls.Kind, $resolved.Until.ToString('o')))
    if (-not (Write-GissueBackoffState $StateFile $state)) {
        # 書けないと次ティックが止まらない。黙って成功したふりをしない。
        $lines += "[BACKOFF][WARN] 状態ファイル '$StateFile' に書けなかった — 次ティックのゲートが効かない(ティック内の中断のみ有効)"
    }
    return @{ Blocked = $true; Kind = $cls.Kind; Until = $resolved.Until; LogLines = $lines }
}
