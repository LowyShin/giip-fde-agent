# [giip 4805] エンジン 0 トークン即死の検知とバックオフ — 単体テスト
# 実行: pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-engine-backoff.ps1
#
# ネットワーク 0。状態ファイルは $env:TEMP 配下の一時ファイルだけを使い、終了時に消す。
# 分類の needle は **実測文面**(2026-10〜11 の 5 種)を literal で pin する。文面が変わったら
# ここが落ちる — 落ちずに静かに検知しなくなる(= 空振り再発)のを避けるため。
$ErrorActionPreference = 'Stop'
. (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../lib/engine-backoff.ps1')).Path

$fail = 0
function Check($name, $ok, $detail) {
    $b = $false
    if ($ok -is [bool]) { $b = $ok } elseif ($null -ne $ok) { $b = [bool]$ok }
    if ($b) { Write-Output "[PASS] $name" } else { $script:fail++; Write-Output "[FAIL] $name - $detail" }
}
$NOW = [datetime]::new(2026, 11, 8, 12, 0, 0, [System.DateTimeKind]::Utc)

# ── 実測文面（giip-4804 ベースラインの transcript から機械抽出した 5 種・件数付き） ──────
$MSG_MONTHLY = "You've hit your monthly spend limit · raise it at https://claude.ai/settings/usage?from=cc_cli_limit_message · your weekly limit resets Oct 26, 9pm (UTC)"  # 370 件
$MSG_WEEKLY_D = "You've hit your weekly limit · resets Nov 2, 9pm (UTC)"   # 50 件
$MSG_WEEKLY_T = "You've hit your weekly limit · resets 9pm (UTC)"          # 2 件
$MSG_SESSION  = "You've hit your session limit · resets 3:50pm (UTC)"      # 10 件
$MSG_LOGIN    = 'Not logged in · Please run /login'                        # 2 件

# ══ (a) 分類 — 実測 5 文面すべてが Blocked になる（B-1） ══════════════════════════
foreach ($c in @(
    @{ N = 'a1 monthly';     T = $MSG_MONTHLY;  K = 'LIMIT_MONTHLY' },
    @{ N = 'a2 weekly+日付'; T = $MSG_WEEKLY_D; K = 'LIMIT_WEEKLY' },
    @{ N = 'a3 weekly 時刻'; T = $MSG_WEEKLY_T; K = 'LIMIT_WEEKLY' },
    @{ N = 'a4 session';     T = $MSG_SESSION;  K = 'LIMIT_SESSION' },
    @{ N = 'a5 未ログイン';  T = $MSG_LOGIN;    K = 'NOT_LOGGED_IN' }
)) {
    $r = Get-GissueEngineBlockKind $c.T
    Check "$($c.N) Blocked"      ($r.Blocked) "reason=$($r.Reason)"
    Check "$($c.N) kind=$($c.K)" ($r.Kind -eq $c.K) "kind=$($r.Kind)"
}
# monthly は「monthly spend limit」と名乗る — weekly に吸われてはいけない(待ち時間が変わる)。
$r = Get-GissueEngineBlockKind $MSG_MONTHLY
Check 'a6 monthly を weekly と誤分類しない' ($r.Kind -ne 'LIMIT_WEEKLY') "kind=$($r.Kind)"
# 実測文面 `Not logged in · Please run /login` は 2 つのパターン(行頭 `Not logged in` と
# 含有 `please run /login`)の **どちらでも**当たる。片方を壊してももう片方が拾うので、
# 実測文面だけでは両者を独立に測れない([[mutant-that-creates-no-harm-survives]])。
# だから「もう片方が当たらない入力」で 1 本ずつ pin する([[every-table-column-needs-its-own-pin]])。
$r = Get-GissueEngineBlockKind 'Not logged in'
Check 'a7 行頭 Not logged in 単独でも検知'  (($r.Blocked) -and ($r.Kind -eq 'NOT_LOGGED_IN')) "kind=$($r.Kind) reason=$($r.Reason)"
$r = Get-GissueEngineBlockKind 'API Error: Invalid API key'
Check 'a8 Invalid API key 単独でも検知'     (($r.Blocked) -and ($r.Kind -eq 'NOT_LOGGED_IN')) "kind=$($r.Kind) reason=$($r.Reason)"
$r = Get-GissueEngineBlockKind 'Error: Overloaded'
Check 'a9 Overloaded 単独でも検知'          (($r.Blocked) -and ($r.Kind -eq 'OVERLOADED')) "kind=$($r.Kind) reason=$($r.Reason)"
# 総称 LIMIT_OTHER: 既知 3 窓に当たらない将来の文面を落とさない。
$r = Get-GissueEngineBlockKind "You've hit your 5-hour limit · resets 4pm (UTC)"
Check 'a10 未知の窓は LIMIT_OTHER で検知'   (($r.Blocked) -and ($r.Kind -eq 'LIMIT_OTHER')) "kind=$($r.Kind) reason=$($r.Reason)"

# ══ (b) B-2: どこかに在るだけでは止めない（自己言及の罠） ════════════════════════
# このスケジューラは**自分自身についてのイシュー**を処理する(giip-4805 がまさにそれ)。
# 働いたセッションの出力に文面が引用されただけで止まると、処理できているのに全停止する。
# 行頭に実文面が来る長い出力（= 러너が検知対象文面を成果物に引用して報告したケース）。
# これは「働いたセッション」なので止めてはいけない。
$longWork = @(
    '이슈 4805 분석을 시작한다. 실측된 즉사 문면은 아래 5종이다:',
    $MSG_WEEKLY_T,
    $MSG_LOGIN,
    '검지 로직을 lib/engine-backoff.ps1 에 구현했다.',
    '테스트 30건을 추가했다.',
    'PR 을 생성했다.'
) -join "`n"
$r = Get-GissueEngineBlockKind $longWork
Check 'b1 実質出力が長ければ Blocked にしない' (-not $r.Blocked) "reason=$($r.Reason)"
Check 'b2 文面一致は記録として残す'             ($r.Kind -eq 'LIMIT_WEEKLY') "kind=$($r.Kind)"
Check 'b3 理由が mention-only'                  ($r.Reason -match 'mention-only') "reason=$($r.Reason)"
# 行頭アンカー: 行の途中に引用されただけなら、出力が 1 行でも即死ではない。
$r = Get-GissueEngineBlockKind "처리 결과: `"$MSG_WEEKLY_T`" 라는 문구를 문서에 적었다"
Check 'b4 行頭でない引用は Blocked にしない'    (-not $r.Blocked) "kind=$($r.Kind) reason=$($r.Reason)"
Check 'b4b 行頭でない引用は一致自体もしない'    (-not $r.Kind) "kind=$($r.Kind)"
# 러너自身のマーカー行は実質出力に数えない(= 実測の即死は [RUN-COUNTS] 等に挟まれている)。
$withMarkers = @('[ENGINE] MiniMax 우선 시도 (model=x)', '[WARN] 뭔가', $MSG_WEEKLY_T) -join "`n"
$r = Get-GissueEngineBlockKind $withMarkers
Check 'b5 러너 마커行に挟まれていても即死と判る' ($r.Blocked) "lines=$($r.MeaningfulLines) reason=$($r.Reason)"
Check 'b6 実質出力行数は 1'                      ($r.MeaningfulLines -eq 1) "lines=$($r.MeaningfulLines)"
$r = Get-GissueEngineBlockKind ''
Check 'b7 空出力は Blocked にしない(文面が無い)' (-not $r.Blocked) "reason=$($r.Reason)"
$r = Get-GissueEngineBlockKind '정상 처리 완료'
Check 'b8 普通の出力は Blocked にしない'         (-not $r.Blocked) "reason=$($r.Reason)"
Check 'b9 一致しなければ kind は空'              (-not $r.Kind) "kind=$($r.Kind)"
# 文字列ではなく配列(Receive-Job の戻り)でも同じ判定になる。
$r = Get-GissueEngineBlockKind @('[RUN-COUNTS] processed=1', $MSG_WEEKLY_T)
Check 'b10 配列入力でも即死と判る'               ($r.Blocked) "reason=$($r.Reason)"
# 閾値は引数で変えられる(呼び出し側が厳しくできる)。
$r = Get-GissueEngineBlockKind $longWork 99
Check 'b11 閾値を上げれば同じ入力が Blocked になる' ($r.Blocked) "reason=$($r.Reason)"
# 大小無視で当てると、ラベルの大小を変えた偽文面まで拾う(PowerShell の -match は既定で大小無視
# — [[powershell-match-contains-are-case-insensitive-by-default]])。-cmatch 固定は意図的な選択であり、
# ここで pin しておかないと黙って -match に戻されても誰も気づかない。
$r = Get-GissueEngineBlockKind "you've hit your weekly limit · resets 9pm (UTC)"
Check 'b12 小文字の偽文面は拾わない(-cmatch 固定)'  (-not $r.Blocked) "kind=$($r.Kind) reason=$($r.Reason)"
$r = Get-GissueEngineBlockKind "YOU'VE HIT YOUR WEEKLY LIMIT · resets 9pm (UTC)"
Check 'b13 大文字の偽文面も拾わない'                (-not $r.Blocked) "kind=$($r.Kind) reason=$($r.Reason)"
# 実測文面(正しい大小)は当然拾う — b12/b13 が「何も拾わないだけ」のテストでないことの対照。
$r = Get-GissueEngineBlockKind $MSG_WEEKLY_T
Check 'b14 実測の大小なら拾う(対照)'                ($r.Blocked) "reason=$($r.Reason)"

# ══ (c) B-3: リセット時刻の解釈 ════════════════════════════════════════════════
$p = ConvertTo-GissueResetUtc 'Nov 2, 9pm' $NOW
Check 'c1 日付あり: 解釈できる'   ($p.Ok) "reason=$($p.Reason)"
# 2026-11-08 現在に最も近い "Nov 2 21:00" は 2026-11-02(=6日前)。年は ±180 日で選ぶ。
Check 'c2 日付あり: 最近接の年'   ($p.Until -eq [datetime]::new(2026, 11, 2, 21, 0, 0, [System.DateTimeKind]::Utc)) "until=$($p.Until.ToString('o'))"
$p = ConvertTo-GissueResetUtc 'Jan 2, 9pm' $NOW
Check 'c3 年越し: 翌年を採る'     ($p.Until -eq [datetime]::new(2027, 1, 2, 21, 0, 0, [System.DateTimeKind]::Utc)) "until=$($p.Until.ToString('o'))"
$p = ConvertTo-GissueResetUtc '3:50pm' $NOW
Check 'c4 時刻のみ: 当日の未来'   ($p.Until -eq [datetime]::new(2026, 11, 8, 15, 50, 0, [System.DateTimeKind]::Utc)) "until=$($p.Until.ToString('o'))"
$p = ConvertTo-GissueResetUtc '9am' $NOW
Check 'c5 時刻のみ: 過ぎていれば翌日' ($p.Until -eq [datetime]::new(2026, 11, 9, 9, 0, 0, [System.DateTimeKind]::Utc)) "until=$($p.Until.ToString('o'))"
$p = ConvertTo-GissueResetUtc '12am' $NOW
Check 'c6 12am = 00:00'           ($p.Until.Hour -eq 0) "until=$($p.Until.ToString('o'))"
$p = ConvertTo-GissueResetUtc '12pm' $NOW
Check 'c7 12pm = 12:00'           ($p.Until.Hour -eq 12) "until=$($p.Until.ToString('o'))"
$p = ConvertTo-GissueResetUtc '' $NOW
Check 'c8 空は Ok=false'          (-not $p.Ok) "reason=$($p.Reason)"
$p = ConvertTo-GissueResetUtc 'next tuesday' $NOW
Check 'c9 未知形式は Ok=false'    (-not $p.Ok) "reason=$($p.Reason)"
$p = ConvertTo-GissueResetUtc '25pm' $NOW
Check 'c10 範囲外の時は Ok=false' (-not $p.Ok) "reason=$($p.Reason)"
# 実測文面から ResetRaw が取れること(分類と解釈が繋がっているか)。
$r = Get-GissueEngineBlockKind $MSG_SESSION
Check 'c11 session 文面から resets を抽出' ($r.ResetRaw -eq '3:50pm') "raw='$($r.ResetRaw)'"
$r = Get-GissueEngineBlockKind $MSG_WEEKLY_D
Check 'c12 weekly 文面から resets を抽出'  ($r.ResetRaw -eq 'Nov 2, 9pm') "raw='$($r.ResetRaw)'"

# ══ (d) B-4: 期限の決定 ═══════════════════════════════════════════════════════
$u = Resolve-GissueBackoffUntil 'LIMIT_SESSION' '3:50pm' 1 $NOW
Check 'd1 session はリセット時刻を使う'   ($u.Source -eq 'reset-time') "note=$($u.Note)"
Check 'd2 リセット+2分の余裕'             ($u.Until -eq [datetime]::new(2026, 11, 8, 15, 52, 0, [System.DateTimeKind]::Utc)) "until=$($u.Until.ToString('o'))"
$u = Resolve-GissueBackoffUntil 'LIMIT_WEEKLY' '9pm' 1 $NOW
Check 'd3 weekly もリセット時刻を使う'    ($u.Source -eq 'reset-time') "note=$($u.Note)"
# B-4 の核心: monthly の文面に添えてあるのは *weekly* のリセット。使えば週次ごとに即死し直す。
$u = Resolve-GissueBackoffUntil 'LIMIT_MONTHLY' 'Oct 26, 9pm' 1 $NOW
Check 'd4 monthly は文面の時刻を使わない' ($u.Source -eq 'exponential') "source=$($u.Source) note=$($u.Note)"
Check 'd5 monthly はその理由を残す'       ($u.Note -match 'weekly') "note=$($u.Note)"
$u = Resolve-GissueBackoffUntil 'NOT_LOGGED_IN' '' 1 $NOW
Check 'd6 未ログインは指数'               ($u.Source -eq 'exponential') "source=$($u.Source)"
# リセット時刻が過去(時刻ずれ・古い出力)なら指数に倒す — 過去を期限にすると即バックオフが切れる。
$u = Resolve-GissueBackoffUntil 'LIMIT_WEEKLY' 'Nov 2, 9pm' 1 $NOW
Check 'd7 過去のリセット時刻は指数に倒す' ($u.Source -eq 'exponential') "source=$($u.Source) note=$($u.Note)"
Check 'd8 期限は必ず現在より未来'         ($u.Until -gt $NOW) "until=$($u.Until.ToString('o'))"
$u = Resolve-GissueBackoffUntil 'LIMIT_WEEKLY' 'next tuesday' 1 $NOW
Check 'd9 解釈不能なら指数に倒す'         ($u.Source -eq 'exponential') "source=$($u.Source) note=$($u.Note)"

# 指数の段差と上限
Check 'd10 1 回目は 20 分(cron 間隔以上)' ((Get-GissueBackoffDelayMinutes 'NOT_LOGGED_IN' 1) -eq 20) "$(Get-GissueBackoffDelayMinutes 'NOT_LOGGED_IN' 1)"
Check 'd11 2 回目は 40 分'                ((Get-GissueBackoffDelayMinutes 'NOT_LOGGED_IN' 2) -eq 40) "$(Get-GissueBackoffDelayMinutes 'NOT_LOGGED_IN' 2)"
Check 'd12 3 回目は 80 分'                ((Get-GissueBackoffDelayMinutes 'NOT_LOGGED_IN' 3) -eq 80) "$(Get-GissueBackoffDelayMinutes 'NOT_LOGGED_IN' 3)"
Check 'd13 未ログインの上限は 360 分'      ((Get-GissueBackoffDelayMinutes 'NOT_LOGGED_IN' 12) -eq 360) "$(Get-GissueBackoffDelayMinutes 'NOT_LOGGED_IN' 12)"
Check 'd14 monthly の上限は 720 分'        ((Get-GissueBackoffDelayMinutes 'LIMIT_MONTHLY' 12) -eq 720) "$(Get-GissueBackoffDelayMinutes 'LIMIT_MONTHLY' 12)"
Check 'd15 overloaded は 30 分で頭打ち'    ((Get-GissueBackoffDelayMinutes 'OVERLOADED' 9) -eq 30) "$(Get-GissueBackoffDelayMinutes 'OVERLOADED' 9)"
Check 'd16 未知種別は既定 360 分で頭打ち'  ((Get-GissueBackoffDelayMinutes 'SOMETHING_NEW' 12) -eq 360) "$(Get-GissueBackoffDelayMinutes 'SOMETHING_NEW' 12)"
Check 'd17 0/負の連続回数でも 1 回目扱い'  ((Get-GissueBackoffDelayMinutes 'NOT_LOGGED_IN' 0) -eq 20) "$(Get-GissueBackoffDelayMinutes 'NOT_LOGGED_IN' 0)"
# 連続回数が異常に大きくても計算が暴走しない(上限で頭打ち)。
Check 'd18 連続 9999 回でも上限どまり'     ((Get-GissueBackoffDelayMinutes 'NOT_LOGGED_IN' 9999) -eq 360) "$(Get-GissueBackoffDelayMinutes 'NOT_LOGGED_IN' 9999)"

# ══ (e) 状態ファイルとゲート（B-5/B-6/B-7） ══════════════════════════════════════
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("gissue_backoff_test_{0}.json" -f [guid]::NewGuid().ToString('N'))
try {
    # 状態なし = バックオフなし・警告なし
    $g = Test-GissueBackoffActive $tmp $NOW 'REPO-MAINT'
    Check 'e1 状態ファイル無しは Active=false' (-not $g.Active) "kind=$($g.Kind)"
    Check 'e2 状態無しで警告は出さない'        (@($g.LogLines).Count -eq 0) "lines=$(@($g.LogLines) -join ' // ')"

    # 即死検知 → 状態が書かれ、固定フォーマットのログが出る
    $s = Set-GissueBackoffFromOutput $tmp $MSG_WEEKLY_T $NOW 'ISSUE:4402'
    Check 'e3 即死で Blocked=true'             ($s.Blocked) "kind=$($s.Kind)"
    Check 'e4 状態ファイルが作られる'          (Test-Path -LiteralPath $tmp) ''
    # B-6: `BACKOFF reason=<kind> until=<ts>` は契約。自由書式ではない。
    $bl = @(@($s.LogLines) | Where-Object { $_ -cmatch '^BACKOFF reason=' })
    Check 'e5 BACKOFF 行がちょうど 1 件'       ($bl.Count -eq 1) "lines=$(@($s.LogLines) -join ' // ')"
    Check 'e6 BACKOFF 行が契約と一致'          ("$($bl[0])" -eq "BACKOFF reason=LIMIT_WEEKLY until=$($s.Until.ToString('o'))") "実際='$($bl[0])'"
    Check 'e7 evidence 行に実文面が載る'       ((@($s.LogLines) -join ' ') -match [regex]::Escape('hit your weekly limit')) "lines=$(@($s.LogLines) -join ' // ')"

    # ゲートが効く（= 次ティックで LLM を起動しない）
    $g = Test-GissueBackoffActive $tmp $NOW 'REPO-MAINT'
    Check 'e8 期限内は Active=true'            ($g.Active) "lines=$(@($g.LogLines) -join ' // ')"
    Check 'e9 ゲートも BACKOFF 行を出す'       ((@($g.LogLines) | Where-Object { $_ -cmatch '^BACKOFF reason=LIMIT_WEEKLY until=' }).Count -eq 1) "lines=$(@($g.LogLines) -join ' // ')"
    Check 'e10 ゲート行に job 名が載る'        ((@($g.LogLines) -join ' ') -match 'job=REPO-MAINT') "lines=$(@($g.LogLines) -join ' // ')"

    # 期限後は通す（永久停止しない）
    $g = Test-GissueBackoffActive $tmp $NOW.AddDays(2) 'REPO-MAINT'
    Check 'e11 期限後は Active=false'          (-not $g.Active) "lines=$(@($g.LogLines) -join ' // ')"
    Check 'e12 期限切れもログに残す'           ((@($g.LogLines) -join ' ') -match '期限切れ') "lines=$(@($g.LogLines) -join ' // ')"

    # 同種別が続けば連続回数が積む
    $s2 = Set-GissueBackoffFromOutput $tmp $MSG_LOGIN $NOW 'ISSUE:4402'
    Check 'e13 別種別は連続を積み直す'         ((@($s2.LogLines) -join ' ') -match 'consecutive=1') "lines=$(@($s2.LogLines) -join ' // ')"
    $s3 = Set-GissueBackoffFromOutput $tmp $MSG_LOGIN $NOW 'ISSUE:4402'
    Check 'e14 同種別は連続を積む'             ((@($s3.LogLines) -join ' ') -match 'consecutive=2') "lines=$(@($s3.LogLines) -join ' // ')"
    Check 'e15 連続 2 回目は待ちが伸びる'      ($s3.Until -gt $s2.Until) "1st=$($s2.Until.ToString('o')) 2nd=$($s3.Until.ToString('o'))"

    # B-7: 実際に動いたら解除
    $s4 = Set-GissueBackoffFromOutput $tmp '정상적으로 처리를 완료했다' $NOW 'ISSUE:4402'
    Check 'e16 正常出力で Blocked=false'       (-not $s4.Blocked) "kind=$($s4.Kind)"
    Check 'e17 正常出力で状態が消える'         (-not (Test-Path -LiteralPath $tmp)) ''
    Check 'e18 解除をログに残す'               ((@($s4.LogLines) -join ' ') -match '解除') "lines=$(@($s4.LogLines) -join ' // ')"

    # B-2 + B-7: 言及しただけのときは「止めない」ことをログで宣言する
    $s5 = Set-GissueBackoffFromOutput $tmp $longWork $NOW 'ISSUE:4805'
    Check 'e19 言及のみは Blocked=false'       (-not $s5.Blocked) "kind=$($s5.Kind)"
    Check 'e20 止めない理由をログに残す'       ((@($s5.LogLines) -join ' ') -match 'バックオフしない') "lines=$(@($s5.LogLines) -join ' // ')"

    # B-5: 壊れた状態ファイルは「止めない」+ 必ず WARN
    Set-Content -LiteralPath $tmp -Value '{ this is not json' -Encoding UTF8
    $g = Test-GissueBackoffActive $tmp $NOW 'REPO-MAINT'
    Check 'e21 壊れた状態でも Active=false'    (-not $g.Active) "lines=$(@($g.LogLines) -join ' // ')"
    Check 'e22 壊れた状態では必ず WARN'        ((@($g.LogLines) | Where-Object { $_ -match '\[BACKOFF\]\[WARN\]' }).Count -ge 1) "lines=$(@($g.LogLines) -join ' // ')"
    # until が解釈できない状態も同じ扱い(黙って通さない)
    Set-Content -LiteralPath $tmp -Value '{"kind":"LIMIT_WEEKLY","until":"not-a-date"}' -Encoding UTF8
    $g = Test-GissueBackoffActive $tmp $NOW 'REPO-MAINT'
    Check 'e23 until 不正でも Active=false'    (-not $g.Active) "lines=$(@($g.LogLines) -join ' // ')"
    Check 'e24 until 不正では必ず WARN'        ((@($g.LogLines) | Where-Object { $_ -match '\[BACKOFF\]\[WARN\]' }).Count -ge 1) "lines=$(@($g.LogLines) -join ' // ')"
    # until が無い JSON も「読めない」側(= WARN 付きで通す)
    Set-Content -LiteralPath $tmp -Value '{"kind":"LIMIT_WEEKLY"}' -Encoding UTF8
    $g = Test-GissueBackoffActive $tmp $NOW 'REPO-MAINT'
    Check 'e25 until 欠落でも WARN 付きで通す' ((-not $g.Active) -and (@($g.LogLines) | Where-Object { $_ -match '\[BACKOFF\]\[WARN\]' }).Count -ge 1) "lines=$(@($g.LogLines) -join ' // ')"
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}

# ══ (f) 러너への配線が実在するか（測り手不在で緑にならないように） ══════════════════
# この lib を書いても呼ばれていなければ意味が無い。ソースに対して配線を直接 pin する。
$runner = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../run-gissue-claude.ps1')).Path
$src = Get-Content -LiteralPath $runner -Raw -Encoding UTF8

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
# ⚠ 「ファイル名がソースのどこかに在るか」で見てはいけない — すぐ上の自分のコメントにも同じ文字列が
#   あるので、닷소싱 行を消しても通ってしまう(giip 4804 の NC で実際に生き残った型:
#   [[substring-anywhere-is-not-an-anchor]] / [[self-search-hits-its-own-literal]])。
#   だから **닷소싱の実行文そのもの**をアンカーにする。
$dotSourceBackoff = ". (Join-Path `$root 'lib/engine-backoff.ps1')"
Check 'f1 러너が lib を닷소싱している(実行文)' ($srcReal.Contains($dotSourceBackoff)) ''
# ⚠ 関数名の前方一致で見てはいけない — `Test-GissueBackoffActiveLater` のような改名を素通りする
#   ([[substring-match-on-numbered-ids-needs-a-boundary]] と同型)。呼び出し式ごと pin する。
$callGate = '$tickBackoff = Test-GissueBackoffActive $backoffStateFile'
Check 'f2 ティックゲートが配線されている'    ($srcReal.Contains($callGate)) ''
# ゲートの結果が実際に使われているか。判定だけして捨てる改変を通さない。
Check 'f2b ゲートの結果が使われている'       ($srcReal.Contains('$engineBlockedThisTick = [bool]$tickBackoff.Active')) ''
# ⚠ 検知の呼び出しは **2 箇所**ある(REPO-MAINT / per-issue)。片方だけ pin すると
#   もう片方を外しても通る([[every-table-column-needs-its-own-pin]])。両方を別々に pin する。
Check 'f3 REPO-MAINT 出力の検知が配線されている' ($srcReal.Contains('$boRepo = Set-GissueBackoffFromOutput $backoffStateFile')) ''
Check 'f3b per-issue 出力の検知が配線されている' ($srcReal.Contains('$boIssue = Set-GissueBackoffFromOutput $backoffStateFile')) ''
# ゲートは REPO-MAINT の Start-Job より前になければ意味が無い(起動してから見ても遅い)。
$idxGate = $srcReal.IndexOf($callGate)
$idxRepoMaintSpawn = $srcReal.IndexOf('$repoMaintJob = Start-Job')
Check 'f4 ゲートが REPO-MAINT spawn より前'  (($idxGate -ge 0) -and ($idxRepoMaintSpawn -ge 0) -and ($idxGate -lt $idxRepoMaintSpawn)) "gate=$idxGate spawn=$idxRepoMaintSpawn"
# イシュー順回でもティック内で止まること(= 1 ティックで全件空振りしない)。
Check 'f5 イシュー順回の中断が配線されている' ($srcReal -match 'BACKOFF-BREAK') ''
Check 'f5b 中断が実際に break している'       ($srcReal.Contains('[BACKOFF-BREAK]') -and ($srcReal.IndexOf('[BACKOFF-BREAK]') -lt $srcReal.IndexOf('if ((Get-Date) -gt $issueLoopDeadline)'))) ''

if ($fail -gt 0) { Write-Output "FAILED: $fail"; exit 1 }
Write-Output 'ALL PASS'
