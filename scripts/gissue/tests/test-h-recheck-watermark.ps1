# [giip 4805] [H] 最近コメント再検証の高水位マーク — 単体テスト
# 実行: pwsh -NoProfile -ExecutionPolicy Bypass -File scripts/gissue/tests/test-h-recheck-watermark.ps1
# ネットワーク 0。一時ファイルのみ使い、終了時に消す。
$ErrorActionPreference = 'Stop'
. (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../lib/h-recheck-watermark.ps1')).Path

$fail = 0
function Check($name, $ok, $detail) {
    $b = $false
    if ($ok -is [bool]) { $b = $ok } elseif ($null -ne $ok) { $b = [bool]$ok }
    if ($b) { Write-Output "[PASS] $name" } else { $script:fail++; Write-Output "[FAIL] $name - $detail" }
}
function HasWarn($r) { return (@(@($r.LogLines) | Where-Object { $_ -match '\[H-WINDOW\]\[WARN\]' }).Count -ge 1) }

$NOW = [datetime]::new(2026, 11, 8, 12, 0, 0, [System.DateTimeKind]::Utc)
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("gissue_hwm_test_{0}.json" -f [guid]::NewGuid().ToString('N'))

try {
    # ── (a) W-1: マーク無しは「従来どおり 2 時間」。0 時間に倒さない ──────────────────
    $r = Resolve-GissueHRecheckHoursBack $tmp '70418' $NOW 2
    Check 'a1 マーク無しは既定 2 時間'      ($r.HoursBack -eq 2) "hours=$($r.HoursBack)"
    Check 'a2 source=default'               ($r.Source -eq 'default') "source=$($r.Source)"
    Check 'a3 マーク無しは WARN でなく通知' (-not (HasWarn $r)) "lines=$(@($r.LogLines) -join ' // ')"
    # W-1 の核心: 絶対に 0 にしない(0 だと list-issues.js 側で窓が無効化され全件対象になる)。
    Check 'a4 窓は 0 にならない'            ($r.HoursBack -gt 0) "hours=$($r.HoursBack)"

    # ── (b) マークがあれば経過時間ぶんだけ ────────────────────────────────────────
    Check 'b1 書き込みが成功する'           (Set-GissueHWatermark $tmp '70418' $NOW.AddMinutes(-20)) ''
    $r = Resolve-GissueHRecheckHoursBack $tmp '70418' $NOW 2
    Check 'b2 20 分前のマーク → 0.3333 時間' ([math]::Abs($r.HoursBack - 0.3333) -lt 0.001) "hours=$($r.HoursBack)"
    Check 'b3 source=watermark'              ($r.Source -eq 'watermark') "source=$($r.Source)"
    Check 'b4 窓が既定より狭い(重複が消える)' ($r.HoursBack -lt 2) "hours=$($r.HoursBack)"
    Check 'b5 ログに前回実行時刻が載る'      ((@($r.LogLines) -join ' ') -match '2026-11-08T11:40') "lines=$(@($r.LogLines) -join ' // ')"

    # ── (c) 取りこぼし防止: 長時間動いていなければ窓は伸びる(cap を置かない) ──────────
    Set-GissueHWatermark $tmp '70418' $NOW.AddDays(-4) | Out-Null
    $r = Resolve-GissueHRecheckHoursBack $tmp '70418' $NOW 2
    Check 'c1 4 日前のマーク → 96 時間'      ([math]::Abs($r.HoursBack - 96) -lt 0.001) "hours=$($r.HoursBack)"
    Check 'c2 既定より広くなることを許す'    ($r.HoursBack -gt 2) "hours=$($r.HoursBack)"
    # 11-05 以降の空転停止から復帰したときに停止中のコメントを落とさない、が c1/c2 の意味。
    Set-GissueHWatermark $tmp '70418' $NOW.AddDays(-400) | Out-Null
    $r = Resolve-GissueHRecheckHoursBack $tmp '70418' $NOW 2
    Check 'c3 400 日前でも切り捨てない'      ($r.HoursBack -gt 9000) "hours=$($r.HoursBack)"

    # ── (d) W-3: 下限。連続起動で 0 にならない ───────────────────────────────────
    Set-GissueHWatermark $tmp '70418' $NOW | Out-Null
    $r = Resolve-GissueHRecheckHoursBack $tmp '70418' $NOW 2
    Check 'd1 経過 0 でも下限で正の値'       ($r.HoursBack -ge 0.05) "hours=$($r.HoursBack)"
    Check 'd2 下限ちょうど'                  ($r.HoursBack -eq 0.05) "hours=$($r.HoursBack)"

    # ── (e) W-4: 未来のマークは既定に倒す(負の窓を作らない) ───────────────────────
    Set-GissueHWatermark $tmp '70418' $NOW.AddHours(5) | Out-Null
    $r = Resolve-GissueHRecheckHoursBack $tmp '70418' $NOW 2
    Check 'e1 未来のマークは既定 2 時間'     ($r.HoursBack -eq 2) "hours=$($r.HoursBack)"
    Check 'e2 未来のマークは WARN を出す'    (HasWarn $r) "lines=$(@($r.LogLines) -join ' // ')"

    # ── (f) CSN 独立 ──────────────────────────────────────────────────────────
    Set-GissueHWatermark $tmp '70418' $NOW.AddMinutes(-20) | Out-Null
    Set-GissueHWatermark $tmp '70424' $NOW.AddMinutes(-60) | Out-Null
    $r18 = Resolve-GissueHRecheckHoursBack $tmp '70418' $NOW 2
    $r24 = Resolve-GissueHRecheckHoursBack $tmp '70424' $NOW 2
    Check 'f1 CSN 70418 は 0.3333 時間'      ([math]::Abs($r18.HoursBack - 0.3333) -lt 0.001) "hours=$($r18.HoursBack)"
    Check 'f2 CSN 70424 は 1 時間'           ([math]::Abs($r24.HoursBack - 1) -lt 0.001) "hours=$($r24.HoursBack)"
    # 片方の前進で他方を消してはいけない。
    Set-GissueHWatermark $tmp '70418' $NOW | Out-Null
    $r24b = Resolve-GissueHRecheckHoursBack $tmp '70424' $NOW 2
    Check 'f3 他 CSN のマークを消さない'     ($r24b.Source -eq 'watermark') "source=$($r24b.Source)"
    $r99 = Resolve-GissueHRecheckHoursBack $tmp '79999' $NOW 2
    Check 'f4 未登録 CSN は既定'             (($r99.HoursBack -eq 2) -and ($r99.Source -eq 'default')) "hours=$($r99.HoursBack)"

    # ── (g) W-1/W-2: 壊れた/不正なマークは既定 + 必ず WARN ───────────────────────
    Set-Content -LiteralPath $tmp -Value '{ broken json' -Encoding UTF8
    $r = Resolve-GissueHRecheckHoursBack $tmp '70418' $NOW 2
    Check 'g1 壊れたファイルは既定 2 時間'   ($r.HoursBack -eq 2) "hours=$($r.HoursBack)"
    Check 'g2 壊れたファイルは必ず WARN'     (HasWarn $r) "lines=$(@($r.LogLines) -join ' // ')"
    Set-Content -LiteralPath $tmp -Value '{"70418":"not-a-date"}' -Encoding UTF8
    $r = Resolve-GissueHRecheckHoursBack $tmp '70418' $NOW 2
    Check 'g3 解釈不能な刻印は既定 2 時間'   ($r.HoursBack -eq 2) "hours=$($r.HoursBack)"
    Check 'g4 解釈不能な刻印は必ず WARN'     (HasWarn $r) "lines=$(@($r.LogLines) -join ' // ')"
    Set-Content -LiteralPath $tmp -Value '{"70418":""}' -Encoding UTF8
    $r = Resolve-GissueHRecheckHoursBack $tmp '70418' $NOW 2
    Check 'g5 空文字の刻印は既定 2 時間'     ($r.HoursBack -eq 2) "hours=$($r.HoursBack)"
    # 壊れたファイルに書き戻せること(自己修復する)。
    Check 'g6 壊れたファイルでも書き直せる'  (Set-GissueHWatermark $tmp '70418' $NOW.AddMinutes(-30)) ''
    $r = Resolve-GissueHRecheckHoursBack $tmp '70418' $NOW 2
    Check 'g7 書き直し後は watermark'        ($r.Source -eq 'watermark') "source=$($r.Source)"

    # ── (h) 既定値の引数が効く / 不正な既定は 2 に倒す ────────────────────────────
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    $r = Resolve-GissueHRecheckHoursBack $tmp '70418' $NOW 6
    Check 'h1 既定値は引数で変わる'          ($r.HoursBack -eq 6) "hours=$($r.HoursBack)"
    $r = Resolve-GissueHRecheckHoursBack $tmp '70418' $NOW 0
    Check 'h2 既定 0 は 2 に倒す(窓を殺さない)' ($r.HoursBack -eq 2) "hours=$($r.HoursBack)"

    # ── (j) W-6: 書き込み失敗を成功扱いにしない ──────────────────────────────────
    # 成功扱いにすると「マークが前進したつもりで実は前進していない」= 重複再検証が静かに残る。
    # 存在しないディレクトリ配下のパスは書けない。
    $badPath = Join-Path (Join-Path ([System.IO.Path]::GetTempPath()) ("gissue_hwm_nodir_{0}" -f [guid]::NewGuid().ToString('N'))) 'mark.json'
    Check 'j1 書けないパスでは $false を返す'  ((Set-GissueHWatermark $badPath '70418' $NOW) -eq $false) "path=$badPath"
    Check 'j2 パス未指定でも $false'           ((Set-GissueHWatermark '' '70418' $NOW) -eq $false) ''
    # 対照: 書けるパスでは $true(j1/j2 が「常に false」のテストでないことを示す)
    Check 'j3 書けるパスでは $true(対照)'      ((Set-GissueHWatermark $tmp '70418' $NOW) -eq $true) ''
} finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}

# ── (i) 러너への配線が実在するか（書いても呼ばれていなければ意味が無い） ──────────────
$runner = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../run-gissue-claude.ps1')).Path
$src = Get-Content -LiteralPath $runner -Raw -Encoding UTF8
# ⚠ ファイル名の「どこかに在るか」で見てはいけない — すぐ上の自分のコメントにも同じ文字列がある
#   ([[self-search-hits-its-own-literal]])。닷소싱の実行文そのものを pin する。
$dotSourceWm = ". (Join-Path `$root 'lib/h-recheck-watermark.ps1')"
Check 'i1 러너が lib を닷소싱している(実行文)' ($src.Contains($dotSourceWm)) ''
Check 'i2 窓の算出が配線されている'          ($src.Contains('$hWindow = Resolve-GissueHRecheckHoursBack $hWatermarkFile $csn')) ''
# マーク前進は「刻印変数を渡して」呼ばれていなければならない。関数名だけの一致では
# 条件(`if ($true)`)に差し替えられても通る。
Check 'i3 マーク前進が配線されている'        ($src.Contains('Set-GissueHWatermark $hWatermarkFile $csn $repoMaintStartedAtUtc')) ''
# 固定 2 を [H] ポートに直接渡していたのが元の姿。そこが置き換わっていることを pin する。
Check 'i4 [H] ポートが固定 2 時間でない'     ($src -match 'Get-GissuePreflightRecentCommentIssues \$listIssuesScript \$csn \$accountsFile \$apiBase \$hWindow\.HoursBack') ''
# マーク前進は REPO-MAINT の出力受領より後(= 実際に動いた後)でなければならない。
$idxRecv = $src.IndexOf('$repoMaintOut = @(Receive-Job')
$idxAdvance = $src.IndexOf('Set-GissueHWatermark $hWatermarkFile')
Check 'i5 マーク前進が出力受領より後'        (($idxRecv -ge 0) -and ($idxAdvance -gt $idxRecv)) "recv=$idxRecv advance=$idxAdvance"
# 窓の算出は REPO-MAINT spawn より前(プリフライトに渡すため)。
$idxWindow = $src.IndexOf('Resolve-GissueHRecheckHoursBack')
$idxSpawn = $src.IndexOf('$repoMaintJob = Start-Job')
Check 'i6 窓の算出が spawn より前'           (($idxWindow -ge 0) -and ($idxWindow -lt $idxSpawn)) "window=$idxWindow spawn=$idxSpawn"
# 刻印は **セッション開始時刻**でなければならない。出力受領後に取ると、セッション中(最大40分)に
# 付いたコメントが次の窓から外れて永久に未検証になる(= 静かな取りこぼし)。
$idxStamp = $src.IndexOf('$repoMaintStartedAtUtc = (Get-Date).ToUniversalTime()')
Check 'i7 刻印の採取が存在する'              ($idxStamp -ge 0) "stamp=$idxStamp"
Check 'i8 刻印の採取が出力受領より前'        (($idxStamp -ge 0) -and ($idxStamp -lt $idxRecv)) "stamp=$idxStamp recv=$idxRecv"

if ($fail -gt 0) { Write-Output "FAILED: $fail"; exit 1 }
Write-Output 'ALL PASS'
