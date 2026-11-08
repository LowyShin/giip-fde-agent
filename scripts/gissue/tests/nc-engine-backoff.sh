#!/usr/bin/env bash
# [giip 4805] test-engine-backoff.ps1 / test-h-recheck-watermark.ps1 の NC（当て直し / mutation）ハーネス
#
# 用途: 「本体 PASS」だけでは当て先が合っている保証にならない。この프로젝트では
#   「先行ガードが本体 PASS・NC 宣言どおりでも、当て直すと新 mutant の大半が SURVIVED」という型が
#   十八度以上繰り返し観測されている。だから **先行ガード(nc-preflight-target.sh)は置き換えず併走**させ、
#   ここでは 4805 で追加した 2 本(バックオフ / [H] 高水位マーク)に意図的な欠陥(mutant)を1件ずつ入れ、
#   対応するテストが必ず赤になる(KILLED)ことを測る。
#   加えて「赤になってはいけない」緑対照(GREEN)も混ぜ、テストが何にでも赤くなる代物でないことを示す。
#
# 処理: 対象ファイルを .ncbak に退避 → mutant 適用 → pwsh でテスト実行 → 復元。復元は trap で必ず行う。
#   書き込みは対象3ファイルとその .ncbak だけ。ネットワーク呼び出しなし。
# 消費先: giip-4805 の結果レポート（合併被覆の根拠）。
#
# 実行: bash scripts/gissue/tests/nc-engine-backoff.sh
set -u
cd "$(dirname "$0")/../../.." || exit 1
BO=scripts/gissue/lib/engine-backoff.ps1
WM=scripts/gissue/lib/h-recheck-watermark.ps1
RUN=scripts/gissue/run-gissue-claude.ps1
T_BO=scripts/gissue/tests/test-engine-backoff.ps1
T_WM=scripts/gissue/tests/test-h-recheck-watermark.ps1

restore() { for f in "$BO" "$WM" "$RUN"; do [ -f "$f.ncbak" ] && mv -f "$f.ncbak" "$f"; done; }
trap restore EXIT INT TERM

# $1 = テストファイル
run_test() { pwsh -NoProfile -ExecutionPolicy Bypass -File "$1" >/tmp/_nc4805_out.txt 2>&1; echo $?; }

killed=0; survived=0; broken=0; green_ok=0; green_bad=0
# $1=ラベル $2=KILLED|GREEN $3=対象ファイル $4=探す文字列 $5=置換文字列 $6=実行するテスト
apply_mutant() {
  local label="$1" expect="$2" file="$3" from="$4" to="$5" test="$6"
  cp -f "$file" "$file.ncbak"
  if ! FROM="$from" TO="$to" python3 -I - "$file" <<'PY'
import os,sys
p=sys.argv[1]
raw=open(p,'rb').read()
bom = raw.startswith(b'\xef\xbb\xbf')
s=raw.decode('utf-8-sig')
f=os.environ['FROM']; t=os.environ['TO']
n=s.count(f)
if n != 1:
    sys.stderr.write('ANCHOR_COUNT=%d\n' % n); sys.exit(3)
s=s.replace(f,t)
open(p,'wb').write((b'\xef\xbb\xbf' if bom else b'')+s.encode('utf-8'))
PY
  then
    echo "[BROKEN] $label — mutant のアンカーが一意に当たらない（当て先ずれ: 先に直すべきはテストでなくこの行）"
    broken=$((broken+1)); mv -f "$file.ncbak" "$file"; return
  fi
  local rc; rc=$(run_test "$test")
  mv -f "$file.ncbak" "$file"
  if [ "$expect" = "KILLED" ]; then
    if [ "$rc" != "0" ]; then
      echo "[KILLED]   $label  ($(grep -c '^\[FAIL\]' /tmp/_nc4805_out.txt) 件の FAIL)"
      killed=$((killed+1))
    else
      echo "[SURVIVED] $label  ← テストが見ていない欠陥"
      survived=$((survived+1))
    fi
  else
    if [ "$rc" = "0" ]; then
      echo "[GREEN-OK] $label  (無害な変更では赤くならない)"
      green_ok=$((green_ok+1))
    else
      echo "[GREEN-BAD] $label ← 無害な変更で赤くなる（過敏なテスト）: $(grep '^\[FAIL\]' /tmp/_nc4805_out.txt | head -3)"
      green_bad=$((green_bad+1))
    fi
  fi
}

echo "=== 前提: mutant なしで両テストが緑であること ==="
for t in "$T_BO" "$T_WM"; do
  rc0=$(run_test "$t")
  if [ "$rc0" != "0" ]; then echo "[ABORT] mutant 適用前から赤い: $t"; grep '^\[FAIL\]' /tmp/_nc4805_out.txt | head; exit 1; fi
  echo "[BASE-OK] $t — $(grep -c '^\[PASS\]' /tmp/_nc4805_out.txt) PASS / 0 FAIL"
done
echo

echo "=== B-1 分類（実測5文面を取りこぼさない） ==="
apply_mutant 'M01 weekly の needle を壊す' KILLED "$BO" \
  "LinePattern = \"^\\s*You've hit your weekly limit\" }" \
  "LinePattern = \"^\\s*You have hit your weekly limit\" }" "$T_BO"
apply_mutant 'M02 session の needle を壊す' KILLED "$BO" \
  "LinePattern = \"^\\s*You've hit your session limit\" }" \
  "LinePattern = \"^\\s*You've hit your SESSION limit\" }" "$T_BO"
apply_mutant 'M03 未ログインの needle を壊す' KILLED "$BO" \
  "LinePattern = '^\\s*Not logged in' }" \
  "LinePattern = '^\\s*Not signed in' }" "$T_BO"
# monthly を weekly の前から後ろに回すと、monthly 文面が総称/weekly に吸われて待ち時間が変わる。
apply_mutant 'M04 monthly の分類を消す(総称に吸わせる)' KILLED "$BO" \
  "@{ Kind = 'LIMIT_MONTHLY'; Anchored = \$true;  LinePattern = \"^\\s*You've hit your monthly\" }," \
  "@{ Kind = 'LIMIT_WEEKLY'; Anchored = \$true;  LinePattern = \"^\\s*You've hit your monthly\" }," "$T_BO"

echo
echo "=== B-2 自己言及の罠（どこかに在るだけでは止めない） ==="
# 行単位・行頭アンカーをやめて blob 含有にすると、работающая セッションの引用で全停止する。
apply_mutant 'M05 weekly の行頭アンカーを外す(行中でも一致)' KILLED "$BO" \
  "LinePattern = \"^\\s*You've hit your weekly limit\" }" \
  "LinePattern = \"You've hit your weekly limit\" }" "$T_BO"
# 行数キャップを外すと、長い正常出力でも Blocked になる = 働いているのに全停止。
apply_mutant 'M06 実質出力行数のキャップを外す' KILLED "$BO" \
  'if ($lines.Count -gt $cap) {' \
  'if ($false) {' "$T_BO"
apply_mutant 'M07 キャップを巨大にする' KILLED "$BO" \
  '$script:GissueBackoffMaxDeathLines = 3' \
  '$script:GissueBackoffMaxDeathLines = 9999' "$T_BO"
# 러너マーカー行を実質出力に数えてしまうと、[ENGINE] 行が付くだけで即死を見落とす。
apply_mutant 'M08 러너マーカー行の除外をやめる' KILLED "$BO" \
  'if ($t -cmatch $script:GissueBackoffRunnerLinePattern) { continue }' \
  'if ($false) { continue }' "$T_BO"
# 大小無視にすると、ラベルの大小を変えた偽文面まで拾う（[[powershell-match-contains-are-case-insensitive-by-default]]）。
apply_mutant 'M09 -cmatch を -match にする(大小無視)' KILLED "$BO" \
  '$m = ($line -cmatch $p.LinePattern) }' \
  '$m = ($line -match $p.LinePattern) }' "$T_BO"

echo
echo "=== B-3 リセット時刻の解釈 ==="
apply_mutant 'M10 日付あり形式の解釈を壊す' KILLED "$BO" \
  "if (\$txt -match '^([A-Za-z]{3,9})\\s+(\\d{1,2}),\\s*(\\d{1,2})(?::(\\d{2}))?\\s*([AaPp])[Mm]\$') {" \
  "if (\$false) {" "$T_BO"
apply_mutant 'M11 時刻のみ形式の解釈を壊す' KILLED "$BO" \
  "} elseif (\$txt -match '^(\\d{1,2})(?::(\\d{2}))?\\s*([AaPp])[Mm]\$') {" \
  "} elseif (\$false) {" "$T_BO"
apply_mutant 'M12 pm を 24 時制に直さない' KILLED "$BO" \
  "if (\$ampm -eq 'p') { if (\$hour -lt 12) { \$h24 = \$hour + 12 } } else { if (\$hour -eq 12) { \$h24 = 0 } }" \
  "if (\$ampm -eq 'p') { if (\$hour -lt 12) { \$h24 = \$hour } } else { if (\$hour -eq 12) { \$h24 = 0 } }" "$T_BO"
apply_mutant 'M13 過ぎた時刻を翌日にしない' KILLED "$BO" \
  'if ($today -le $NowUtc) { $today = $today.AddDays(1) }' \
  'if ($false) { $today = $today.AddDays(1) }' "$T_BO"
apply_mutant 'M14 年の最近接選択をやめる(常に今年)' KILLED "$BO" \
  'foreach ($yOff in @(0, 1, -1)) {' \
  'foreach ($yOff in @(0)) {' "$T_BO"
apply_mutant 'M15 resets の抽出をやめる' KILLED "$BO" \
  "if (\$hitLine -match 'resets\\s+(.+?)(?:\\s*\\(UTC\\))?\\s*\$') { \$result.ResetRaw = \$Matches[1].Trim() }" \
  "if (\$false) { \$result.ResetRaw = '' }" "$T_BO"

echo
echo "=== B-4 月次は文面のリセット時刻を使わない（別の窓） ==="
apply_mutant 'M16 月次でも文面の時刻を使う' KILLED "$BO" \
  "\$script:GissueBackoffIgnoreResetKinds = @('LIMIT_MONTHLY', 'NOT_LOGGED_IN', 'OVERLOADED')" \
  "\$script:GissueBackoffIgnoreResetKinds = @('NOT_LOGGED_IN', 'OVERLOADED')" "$T_BO"
apply_mutant 'M17 過去のリセット時刻をそのまま期限にする' KILLED "$BO" \
  'if ($p.Until -gt $NowUtc) {' \
  'if ($true) {' "$T_BO"
apply_mutant 'M18 指数バックオフを定数にする' KILLED "$BO" \
  '$delay = [int]($script:GissueBackoffBaseMinutes * [math]::Pow(2, ($n - 1)))' \
  '$delay = [int]$script:GissueBackoffBaseMinutes' "$T_BO"
apply_mutant 'M19 上限(cap)を効かせない' KILLED "$BO" \
  'if ($delay -gt $cap) { $delay = $cap }' \
  'if ($false) { $delay = $cap }' "$T_BO"
apply_mutant 'M20 基準分を cron 間隔より短くする' KILLED "$BO" \
  '$script:GissueBackoffBaseMinutes = 20' \
  '$script:GissueBackoffBaseMinutes = 5' "$T_BO"

echo
echo "=== B-5/B-6/B-7 状態ファイル・ログ契約・解除 ==="
# 読めない状態ファイルで黙って通すと「測り手不在で永久に緑」になる。
apply_mutant 'M21 壊れた状態ファイルで WARN を出さない' KILLED "$BO" \
  'LogLines = @("[BACKOFF][WARN] $($r.Error) — バックオフなしとして従来どおり起動する(起動すれば即死時に状態が書き直される)")' \
  'LogLines = @()' "$T_BO"
apply_mutant 'M22 until 不正で WARN を出さない' KILLED "$BO" \
  "LogLines = @(\"[BACKOFF][WARN] until='\$(\$r.State.until)' を日時として解釈できない — バックオフなしとして従来どおり起動する\")" \
  'LogLines = @()' "$T_BO"
# 逆向きの事故: 読めないファイルで**止めて**しまうと全処理が静かに停止する。
# 1行だけ差し替える(複数行を注入すると構文エラーで赤くなり、"欠陥を見た"のか
#  "壊れただけ"なのか区別できない mutant になる)。
apply_mutant 'M23 壊れた状態ファイルで止めてしまう' KILLED "$BO" \
  "Active = \$false; Kind = ''; Until = \$null; LogLines = @(\"[BACKOFF][WARN] \$(\$r.Error)" \
  "Active = \$true; Kind = ''; Until = \$null; LogLines = @(\"[BACKOFF][WARN] \$(\$r.Error)" "$T_BO"
apply_mutant 'M24 BACKOFF 行のフォーマットを崩す' KILLED "$BO" \
  "\$script:GissueBackoffLogFormat = 'BACKOFF reason={0} until={1}'" \
  "\$script:GissueBackoffLogFormat = 'BACKOFF: reason={0}, until={1}'" "$T_BO"
apply_mutant 'M25 期限切れでも止め続ける' KILLED "$BO" \
  'if ($until -le $NowUtc) {' \
  'if ($false) {' "$T_BO"
apply_mutant 'M26 働いても状態を解除しない' KILLED "$BO" \
  'if (Clear-GissueBackoffState $StateFile) {' \
  'if ($false) {' "$T_BO"
apply_mutant 'M27 連続回数を積まない(待ちが伸びない)' KILLED "$BO" \
  'if ($pk -eq $cls.Kind -and $pc -gt 0) { $consecutive = $pc + 1 }' \
  'if ($false) { $consecutive = $pc + 1 }' "$T_BO"
apply_mutant 'M28 別種別でも連続を積む' KILLED "$BO" \
  '$pk -eq $cls.Kind -and $pc -gt 0' \
  '$pc -gt 0' "$T_BO"

echo
echo "=== 러너 배선（書いても呼ばれていなければ意味が無い） ==="
# ⚠ [giip 4806] 下の 5 件のアンカーは、行頭の改行＋実運転側のインデントまで含めている。
#   理由(実測): giip 4806 が `-DryRun` 分岐にも同じ判定を通したため、同じ呼び出し文が
#   **2 箇所**に出るようになった(DryRun 側は 4 スペース深い)。インデント無しの短いアンカーは
#   両方に当たり、mutant が BROKEN(当て先ずれ)になって**測れなくなる**。
#   mutant 自体は 1 行も弱めていない — 当てる場所を一意にしただけである。
apply_mutant 'M29 backoff lib の닷소싱을 지운다' KILLED "$RUN" \
  $'\n        . (Join-Path $root \'lib/engine-backoff.ps1\')' \
  $'\n        # (닷소싱 제거: NC mutant)' "$T_BO"
apply_mutant 'M30 ティックゲートを外す(常に起動)' KILLED "$RUN" \
  '$engineBlockedThisTick = [bool]$tickBackoff.Active' \
  '$engineBlockedThisTick = $false' "$T_BO"
apply_mutant 'M31 イシュー順回のティック内中断を外す' KILLED "$RUN" \
  '[BACKOFF-BREAK] 엔진 0 토큰 즉사' \
  '[BACKOFF-NOBREAK] 엔진 0 토큰 즉사' "$T_BO"
apply_mutant 'M32 REPO-MAINT 出力の検知を外す' KILLED "$RUN" \
  '$boRepo = Set-GissueBackoffFromOutput $backoffStateFile' \
  '$boRepo = Skip-GissueBackoffFromOutput $backoffStateFile' "$T_BO"
# ゲートが spawn より後ろにあっては意味が無い（起動してから見ても遅い）。
apply_mutant 'M33 ゲートを REPO-MAINT spawn より後ろに置く' KILLED "$RUN" \
  $'\n        $tickBackoff = Test-GissueBackoffActive $backoffStateFile' \
  $'\n        $tickBackoff = Test-GissueBackoffActiveLater $backoffStateFile' "$T_BO"

echo
echo "=== W-1〜W-6 [H] 高水位マーク ==="
# 窓を 0 にすると list-issues.js 側で窓が無効化され「絞ったつもりが全件対象」になる。
apply_mutant 'M34 窓の下限を 0 にする' KILLED "$WM" \
  '$script:GissueHWatermarkMinHours = 0.05' \
  '$script:GissueHWatermarkMinHours = 0' "$T_WM"
apply_mutant 'M35 下限を効かせない' KILLED "$WM" \
  'if ($hours -lt $script:GissueHWatermarkMinHours) { $hours = $script:GissueHWatermarkMinHours }' \
  'if ($false) { $hours = $script:GissueHWatermarkMinHours }' "$T_WM"
# マーク無しで 0 に倒すと [H] が静かに死ぬ（= 一番やってはいけない失敗）。
apply_mutant 'M36 マーク無しで 0 時間に倒す' KILLED "$WM" \
  "return @{ HoursBack = \$def; Source = 'default'; LogLines = @(\"[H-WINDOW] 高水位マーク未設定(csn=\$Csn) — 既定 \${def}時間窓(従来動作)\") }" \
  "return @{ HoursBack = 0; Source = 'default'; LogLines = @(\"[H-WINDOW] 高水位マーク未設定\") }" "$T_WM"
apply_mutant 'M37 読めないときに WARN を出さない' KILLED "$WM" \
  "LogLines = @(\"[H-WINDOW][WARN] \$(\$r.Error) — 既定 \${def}時間窓に倒す(従来動作)\")" \
  'LogLines = @()' "$T_WM"
apply_mutant 'M38 未来のマークで負の窓を作る' KILLED "$WM" \
  'if ($r.Stamp -gt $NowUtc) {' \
  'if ($false) {' "$T_WM"
# cap を入れると長時間停止から復帰したときに停止中のコメントを落とす。
apply_mutant 'M39 窓に上限(24h)を入れる' KILLED "$WM" \
  '$rounded = [math]::Round($hours, 4)' \
  '$rounded = [math]::Round([math]::Min($hours, 24), 4)' "$T_WM"
apply_mutant 'M40 他 CSN のマークを引き継がない' KILLED "$WM" \
  'foreach ($p in $obj.PSObject.Properties) { $map[$p.Name] = "$($p.Value)" }' \
  'if ($false) { $map = @{} }' "$T_WM"
apply_mutant 'M41 既定 0 を 2 に倒さない' KILLED "$WM" \
  'if ($def -le 0) { $def = 2 }' \
  'if ($false) { $def = 2 }' "$T_WM"
apply_mutant 'M42 書き込み失敗を成功扱いにする' KILLED "$WM" \
  '    } catch {
        return $false
    }
}' \
  '    } catch {
        return $true
    }
}' "$T_WM"
apply_mutant 'M43 [H] ポートを固定 2 時間に戻す' KILLED "$RUN" \
  $'\n                ListRecentCommentIssues = { Get-GissuePreflightRecentCommentIssues $listIssuesScript $csn $accountsFile $apiBase $hWindow.HoursBack }' \
  $'\n                ListRecentCommentIssues = { Get-GissuePreflightRecentCommentIssues $listIssuesScript $csn $accountsFile $apiBase 2 }' "$T_WM"
apply_mutant 'M44 マーク前進の配線を外す' KILLED "$RUN" \
  'if (Set-GissueHWatermark $hWatermarkFile $csn $repoMaintStartedAtUtc) {' \
  'if ($true) {' "$T_WM"
apply_mutant 'M45 watermark lib の닷소싱을 지운다' KILLED "$RUN" \
  $'\n        . (Join-Path $root \'lib/h-recheck-watermark.ps1\')' \
  $'\n        # (닷소싱 제거: NC mutant)' "$T_WM"
# 刻印を終了時刻にすると、セッション中に付いたコメントが次の窓から外れて永久に未検証になる。
apply_mutant 'M46 刻印を spawn 前でなく出力受領後に取る' KILLED "$RUN" \
  '        $repoMaintStartedAtUtc = (Get-Date).ToUniversalTime()
        try {' \
  '        try {' "$T_WM"

echo
echo "=== 緑対照（赤くなってはいけない変更） ==="
apply_mutant 'G01 backoff lib のコメント文言を変える' GREEN "$BO" \
  '# ── 純粋関数: 実質出力行の抽出（B-2 b） ─────────────────────────────────────────' \
  '# ── 純粋関数: 実質出力行の抽出（コメント変更のみ） ──' "$T_BO"
apply_mutant 'G02 watermark lib のコメント文言を変える' GREEN "$WM" \
  '$script:GissueHWatermarkMinHours = 0.05   # 3 分。W-3 の下限。' \
  '$script:GissueHWatermarkMinHours = 0.05   # 下限(コメント変更のみ)。' "$T_WM"
apply_mutant 'G03 러너のログ文言だけ変える' GREEN "$RUN" \
  'へ前進(csn=$csn)' \
  'へ更新(csn=$csn)' "$T_WM"
# ⚠ cap 表(例: OVERLOADED=30)は**契約**なので緑対照には使えない — 変えればテストが赤くなるのが正しい
#   (初版でそれを緑対照にして GREEN-BAD が出た。過敏なテストではなく、こちらの対照の選び方が誤り)。
#   緑対照は「判定に一切関与しない文字列」を選ぶ。
apply_mutant 'G04 BACKOFF 情報行(契約外)の文言を変える' GREEN "$BO" \
  '0 토큰 즉사 검지' \
  '0 토큰 즉사 감지' "$T_BO"

echo
echo "================ NC 結果 ================"
echo "KILLED   : $killed"
echo "SURVIVED : $survived"
echo "BROKEN   : $broken   (mutant のアンカーが一意に当たらなかった = 当て先ずれ)"
echo "GREEN-OK : $green_ok"
echo "GREEN-BAD: $green_bad"
total=$((killed+survived))
echo "kill rate: $killed/$total"
if [ "$survived" -gt 0 ] || [ "$broken" -gt 0 ] || [ "$green_bad" -gt 0 ]; then
  echo "NC: 未達 — SURVIVED/BROKEN/GREEN-BAD が 0 でない"
  exit 1
fi
echo "NC: 全 mutant KILLED・緑対照も緑"
