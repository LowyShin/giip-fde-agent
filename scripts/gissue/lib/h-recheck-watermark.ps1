# h-recheck-watermark.ps1 — [H] 最近コメント再検証の「高水位マーク」（giip 4805）
#
# 用途
#   REPO-MAINT セッションの [H] 規則(プロンプト本文 `[H] 최근 코멘트 논리 재검증`, giip #1162)は
#   `list-issues.js --hours-back 2` で「直近 2 時間にコメントが付いた issue」を対象にする。
#   ところが러너は cron `7,27,47`(=20 分間隔)で回るので、**同じコメントが約 6 ティック続けて
#   対象に入り、同じ事実主張を 6 回再検証する**(結果は毎回同じ)。1 回あたり実測中央値
#   1,456,098 トークン(giip-4804 ベースライン)なので、この重複がそのまま費用になる。
#
#   [H] 自体は「コメントと実態の再検証」= **LLM 判断が必要な層**で、本タスクの削減対象外である
#   (依頼本文の範囲と制約が明示)。だからここでは**判断の中身を一切変えない**。
#   変えるのは窓の取り方だけ: 固定 2 時間 → 「前回 [H] を実際に回した時刻から今まで」。
#   同一コメントの重複再検証が消えるだけで、どのコメントも最低 1 回は必ず対象に入る。
#
# 取りこぼしが原理的に起きない理由（この設計の肝）
#   マークは **REPO-MAINT セッションが実際に動いたときだけ**前進させる。
#   プリフライトで skip した / 0 トークン即死した / 캡 초과で止めた ティックでは前進させない。
#   よって回らなかった間は窓が伸び続け、次に回ったときにまとめて拾う。**上限(cap)は置かない** —
#   「窓が長すぎるから切る」を入れると、長時間停止(実際に 11-05 以降停止している)から復帰した
#   ときに停止中のコメントを丸ごと落とす。切るほうが危ないので切らない。
#
# 処理内容 / 保存先 / 消費先（コード文書化規則）
#   - 処理: 状態ファイルの読み書きと経過時間の算出のみ。**ネットワーク呼び出し 0 件**。
#   - 保存先: `<logDir>/h_recheck_watermark.json`。形式 `{ "<csn>": "<ISO8601 UTC>" }`(CSN 別)。
#   - 消費先: run-gissue-claude.ps1 の
#             (1) プリフライト [H] ポートに渡す `--hours-back` の値
#             (2) REPO-MAINT セッションが実際に動いた直後のマーク前進
#             tests/test-h-recheck-watermark.ps1。
#
# 判定契約（W-1〜W-6）
#   W-1 マークが無い/読めない/解釈できないときは **既定(2時間)に倒す** = 従来どおりの動作。
#       黙って 0 時間(= [H] 対象なし)に倒すことは絶対にしない — それは「静かに [H] を殺す」。
#   W-2 W-1 のとき必ず理由をログに残す(`[H-WINDOW]` 行)。測り手不在で緑になる経路を作らない。
#   W-3 窓は常に **正の値**。経過が極小(連続起動)でも下限 $MinHours(0.05h=3分)を割らない
#       — 0 を渡すと list-issues.js 側が `HOURS_BACK > 0` 判定で窓無効=全件対象になり、
#       「絞ったつもりが逆に全件」になる(実装を読んで確認した実際の分岐)。
#   W-4 マークが未来(時刻ずれ)なら既定に倒す。負の窓を作らない。
#   W-5 前進させるのは呼び出し側が「実際に動いた」と判断したときだけ。このファイルは
#       自分では前進させない(= 判定と副作用を混ぜない)。
#   W-6 書き込み失敗は黙って成功扱いにしない。false を返し、呼び出し側が WARN を出す。
#
# PowerShell 5.1 互換(`??` / 三項演算子 / null 条件演算子は使わない)。

$script:GissueHWatermarkMinHours = 0.05   # 3 分。W-3 の下限。

function Get-GissueHWatermarkPath($LogDir) {
    return (Join-Path $LogDir 'h_recheck_watermark.json')
}

# 返り値: @{ Ok; Stamp([datetime] or $null); Error }
function Read-GissueHWatermark($StateFile, $Csn) {
    if (-not $StateFile) { return [pscustomobject]@{ Ok = $false; Stamp = $null; Error = 'マークファイルのパスが未指定' } }
    if (-not (Test-Path -LiteralPath $StateFile)) { return [pscustomobject]@{ Ok = $true; Stamp = $null; Error = '' } }
    try {
        $raw = Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8
        if (-not "$raw".Trim()) { return [pscustomobject]@{ Ok = $true; Stamp = $null; Error = '' } }
        $obj = $raw | ConvertFrom-Json
        if ($null -eq $obj) { return [pscustomobject]@{ Ok = $false; Stamp = $null; Error = 'マークファイルが JSON として空' } }
        $prop = $obj.PSObject.Properties["$Csn"]
        if ($null -eq $prop) { return [pscustomobject]@{ Ok = $true; Stamp = $null; Error = '' } }
        $val = "$($prop.Value)"
        if (-not $val.Trim()) { return [pscustomobject]@{ Ok = $true; Stamp = $null; Error = '' } }
        $parsed = [datetime]::Parse($val, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()
        return [pscustomobject]@{ Ok = $true; Stamp = $parsed; Error = '' }
    } catch {
        return [pscustomobject]@{ Ok = $false; Stamp = $null; Error = "マークファイル読み取り/解釈失敗: $($_.Exception.Message)" }
    }
}

# [H] に渡す --hours-back を決める。返り値: @{ HoursBack; Source; LogLines }
#   Source: 'watermark'(マークからの経過) / 'default'(マーク無し・異常)
function Resolve-GissueHRecheckHoursBack($StateFile, $Csn, [datetime]$NowUtc, [double]$DefaultHours = 2) {
    $def = $DefaultHours
    if ($def -le 0) { $def = 2 }
    $r = Read-GissueHWatermark $StateFile $Csn
    if (-not $r.Ok) {
        # W-1/W-2: 読めないときは従来どおりの 2 時間窓。黙って通さない。
        return @{ HoursBack = $def; Source = 'default'; LogLines = @("[H-WINDOW][WARN] $($r.Error) — 既定 ${def}時間窓に倒す(従来動作)") }
    }
    if ($null -eq $r.Stamp) {
        return @{ HoursBack = $def; Source = 'default'; LogLines = @("[H-WINDOW] 高水位マーク未設定(csn=$Csn) — 既定 ${def}時間窓(従来動作)") }
    }
    if ($r.Stamp -gt $NowUtc) {
        # W-4: 未来のマーク(時刻ずれ)。負の窓にしない。
        return @{ HoursBack = $def; Source = 'default'; LogLines = @("[H-WINDOW][WARN] マークが未来($($r.Stamp.ToString('o')))— 時刻ずれとみて既定 ${def}時間窓に倒す") }
    }
    $hours = ($NowUtc - $r.Stamp).TotalHours
    # W-3: 0 を渡すと list-issues.js 側が窓無効(全件対象)になる。下限で必ず正にする。
    if ($hours -lt $script:GissueHWatermarkMinHours) { $hours = $script:GissueHWatermarkMinHours }
    $rounded = [math]::Round($hours, 4)
    return @{
        HoursBack = $rounded
        Source    = 'watermark'
        LogLines  = @("[H-WINDOW] 前回 [H] 実行 $($r.Stamp.ToString('o')) から ${rounded}時間ぶんだけを対象にする(固定2時間窓の重複再検証を外す)")
    }
}

# マークを前進させる。**呼び出し側が「実際に動いた」と判断したときだけ**呼ぶ(W-5)。
# 返り値: $true/$false(W-6 — 失敗を成功扱いにしない)
function Set-GissueHWatermark($StateFile, $Csn, [datetime]$StampUtc) {
    if (-not $StateFile) { return $false }
    try {
        $map = @{}
        if (Test-Path -LiteralPath $StateFile) {
            $raw = Get-Content -LiteralPath $StateFile -Raw -Encoding UTF8
            if ("$raw".Trim()) {
                $obj = $null
                try { $obj = $raw | ConvertFrom-Json } catch { $obj = $null }
                if ($null -ne $obj) {
                    # 他 CSN のマークを消さない(CSN ごとに独立)。
                    foreach ($p in $obj.PSObject.Properties) { $map[$p.Name] = "$($p.Value)" }
                }
            }
        }
        $map["$Csn"] = $StampUtc.ToUniversalTime().ToString('o')
        ($map | ConvertTo-Json -Depth 3) | Out-File -FilePath $StateFile -Encoding UTF8
        return $true
    } catch {
        return $false
    }
}
