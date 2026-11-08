#!/usr/bin/env bash
# [giip 4806] test-spawn-gate-order.ps1 の NC（当て直し / mutation）ハーネス
#
# 用途: 「本体 PASS」は当て先が合っている保証にならない（先行ガードが本体 PASS・NC 宣言どおりでも、
#   当て直すと新 mutant の大半が生き残る型が二十度繰り返されている）。ここでは
#   lib/spawn-gate-audit.ps1 と run-gissue-claude.ps1 に意図的な欠陥(mutant)を 1 件ずつ入れ、
#   test-spawn-gate-order.ps1 が必ず赤になる(KILLED)ことを測る。
#   加えて「赤になってはいけない」緑対照(GREEN)も混ぜ、何にでも赤くなる代物でないことを示す。
#
# 先行ガード(nc-preflight-target.sh / nc-engine-backoff.sh)は**置き換えず併走**させる。
#   被覆は合併で測る（このハーネス単独の KILL 数は被覆の証明にならない）。
#
# 処理: 対象ファイルを .ncbak に退避 → mutant 適用 → pwsh でテスト実行 → 復元。
#   復元は trap で必ず行う。書き込みは対象 2 ファイルとその .ncbak、/tmp の出力だけ。
# 消費先: giip-4806 の結果レポート（合併被覆の根拠）。
#
# 実行: bash scripts/gissue/tests/nc-spawn-gate-order.sh
set -u
cd "$(dirname "$0")/../../.." || exit 1
LIB=scripts/gissue/lib/spawn-gate-audit.ps1
RUN=scripts/gissue/run-gissue-claude.ps1
TEST=scripts/gissue/tests/test-spawn-gate-order.ps1

restore() { for f in "$LIB" "$RUN"; do [ -f "$f.ncbak" ] && mv -f "$f.ncbak" "$f"; done; }
trap restore EXIT INT TERM

run_test() { pwsh -NoProfile -ExecutionPolicy Bypass -File "$TEST" >/tmp/_nc4806_out.txt 2>&1; echo $?; }

killed=0; survived=0; broken=0; green_ok=0; green_bad=0
# $1=ラベル $2=KILLED|GREEN $3=ファイル $4=探す文字列 $5=置換文字列
apply_mutant() {
  local label="$1" expect="$2" file="$3" from="$4" to="$5"
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
    echo "[BROKEN] $label — mutant のアンカーが一意に当たらない（当て先ずれ: 先に直すのはテストでなくこの行）"
    broken=$((broken+1)); mv -f "$file.ncbak" "$file"; return
  fi
  local rc; rc=$(run_test)
  mv -f "$file.ncbak" "$file"
  if [ "$expect" = "KILLED" ]; then
    if [ "$rc" != "0" ]; then
      echo "[KILLED]   $label  ($(grep -c '^\[FAIL\]' /tmp/_nc4806_out.txt) 件の FAIL)"
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
      echo "[GREEN-BAD] $label ← 無害な変更で赤くなる（過敏なテスト）: $(grep '^\[FAIL\]' /tmp/_nc4806_out.txt | head -3)"
      green_bad=$((green_bad+1))
    fi
  fi
}

echo "=== 前提: mutant なしで本体が緑であること ==="
rc0=$(run_test)
if [ "$rc0" != "0" ]; then echo "[ABORT] mutant 適用前からテストが赤い"; grep '^\[FAIL\]' /tmp/_nc4806_out.txt | head; exit 1; fi
echo "[BASE-OK] $(grep -c '^\[PASS\]' /tmp/_nc4806_out.txt) PASS / 0 FAIL"
echo

echo "=== S-1/S-3: 測り手不在・解析不能を緑にしない ==="
apply_mutant "M01 空ソースを Ok=true にする" KILLED "$LIB" \
  '        return (New-GissueSpawnAuditResult $false "ソースが空: $SourcePath")' \
  '        return (New-GissueSpawnAuditResult $true "ソースが空: $SourcePath")'
apply_mutant "M02 構文エラーを無視する" KILLED "$LIB" \
  '    if ($null -ne $errors -and @($errors).Count -gt 0) {' \
  '    if ($false) {'
apply_mutant "M03 spawn 点 0 件で Ok=true(rule 42 違反)" KILLED "$LIB" \
  '    if ($sites.Count -eq 0) {
        $res.Ok = $false' \
  '    if ($sites.Count -eq 0) {
        $res.Ok = $true'
apply_mutant "M04 ファイル不在を Ok=true にする" KILLED "$LIB" \
  '        return (New-GissueSpawnAuditResult $false "検査対象が見つからない: $Path")' \
  '        return (New-GissueSpawnAuditResult $true "検査対象が見つからない: $Path")'
apply_mutant "M05 違反があっても Ok=true にする" KILLED "$LIB" \
  '    $res.Ok = (@($res.Violations).Count -eq 0)' \
  '    $res.Ok = $true'

echo
echo "=== S-2: spawn 点の検出 ==="
apply_mutant "M06 claude 直接起動を検出しない" KILLED "$LIB" \
  "        if (-not [string]::Equals(\"\$name\", 'claude', [System.StringComparison]::OrdinalIgnoreCase)) { continue }" \
  '        if ($true) { continue }'
apply_mutant "M07 Start-Job を検出しない" KILLED "$LIB" \
  "        if (-not [string]::Equals(\"\$name\", 'Start-Job', [System.StringComparison]::OrdinalIgnoreCase)) { continue }" \
  '        if ($true) { continue }'
apply_mutant "M08 エンジン呼び出しの有無を見ずに全 Start-Job を spawn 点にする" KILLED "$LIB" \
  '        if ($inner.Count -eq 0) { continue }' \
  '        if ($false) { continue }'
apply_mutant "M09 木の走査を最上位だけにする(入れ子の起動を見落とす)" KILLED "$LIB" \
  '    $cmds = @($RootAst.FindAll({ param($a) $a -is [System.Management.Automation.Language.CommandAst] }, $true))
    foreach ($c in $cmds) {
        $name = $c.GetCommandName()
        if ($null -eq $name) { continue }
        # S-8: 識別子なので大小は無視する。`& Claude -p` も PowerShell は同じ claude を起動する。' \
  '    $cmds = @($RootAst.FindAll({ param($a) $a -is [System.Management.Automation.Language.CommandAst] }, $false))
    foreach ($c in $cmds) {
        $name = $c.GetCommandName()
        if ($null -eq $name) { continue }
        # S-8: 識別子なので大小は無視する。`& Claude -p` も PowerShell は同じ claude を起動する。'
apply_mutant "M10 起動点のキーを関数境界を越えて潰す(別の起動が同一キーになる)" KILLED "$LIB" \
  '        if ($cur -is [System.Management.Automation.Language.FunctionDefinitionAst]) { break }' \
  '        if ($false) { break }'
apply_mutant "M11 流し込み変数ではなく代入先だけを見る(エンジン内の2本を区別できない)" KILLED "$LIB" \
  '    if ($parent -is [System.Management.Automation.Language.PipelineAst]) {' \
  '    if ($false) {'

echo
echo "=== S-4: レジスタ照合は両方向 ==="
apply_mutant "M12 未登録の起動点を違反にしない" KILLED "$LIB" \
  '            $violations += "S-4: 未登録の LLM 起動点' \
  '            $ignored = "S-4: 未登録の LLM 起動点'
apply_mutant "M13 消えた登録点を違反にしない" KILLED "$LIB" \
  '            $violations += "S-4: レジスタの '"'"'$($r.Key)'"'"' が見つからない' \
  '            $ignored = "S-4: レジスタの '"'"'$($r.Key)'"'"' が見つからない'
apply_mutant "M14 テスト用レジスタを無視して常に正本を使う" KILLED "$LIB" \
  '    if ($null -ne $RegistryOverride) { $registry = @($RegistryOverride) }' \
  '    if ($false) { $registry = @($RegistryOverride) }'

echo
echo "=== S-5: 順序でなく内包で見る（先行ガードに無い被覆） ==="
apply_mutant "M15 内包判定を常に真にする" KILLED "$LIB" \
  '            if ($condText.IndexOf('"'"'$preflightDecision.Spawn'"'"', [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {' \
  '            if ($true) {'
# M16 は **害を生まない等価 mutant** だと実測で確認した(2026-11-08)。
#   Else 節が無いとき `$parent.ElseClause.Extent.StartOffset` は $null になり、
#   直後の範囲比較 `$Site.Offset -lt $null`(= < 0) が必ず偽になるので、
#   null 検査を外しても判定結果は 1 文字も変わらない(同じ違反文が出ることを両方で確認済み)。
#   = null 検査は防御的な冗長。KILLED を期待する mutant ではなく**緑対照**として置く
#   （生き残ったものを黙って消すと「当て先の穴」と「無害な変更」の区別が消える）。
apply_mutant "M16 Else 節の null 検査を外す(等価 mutant・判定は変わらない)" GREEN "$LIB" \
  '                if ($null -ne $parent.ElseClause) {' \
  '                if ($true -or ($null -ne $parent.ElseClause)) {'
apply_mutant "M17 Else 節の範囲チェックを捨てる(どこに在っても内包扱い)" KILLED "$LIB" \
  '                    if ($Site.Offset -ge $eo -and $Site.Offset -lt $ec) { return $true }' \
  '                    if ($true) { return $true }'
apply_mutant "M18 内包していなくても違反にしない" KILLED "$LIB" \
  '                $violations += "S-5:' '                $ignored = "S-5:'
apply_mutant "M19 内包判定の結果を使わない(常に通す)" KILLED "$LIB" \
  '            if (-not (Test-GissueSiteInsidePreflightElse $s)) {' \
  '            if ($false) {'

echo
echo "=== S-6: per-issue は「ループ内で break する判定が spawn より前」 ==="
apply_mutant "M20 break の有無を見ない(ログだけで通す)" KILLED "$LIB" \
  '                if ($breaks.Count -eq 0) { continue }' \
  '                if ($false) { continue }'
apply_mutant "M21 break 判定が spawn の後でも通す" KILLED "$LIB" \
  '                if ($if.Extent.StartOffset -lt $Site.Offset) { return $true }' \
  '                if ($true) { return $true }'
apply_mutant "M22 条件が \$engineBlockedThisTick かを見ない" KILLED "$LIB" \
  '                if ($condText.IndexOf('"'"'$engineBlockedThisTick'"'"', [System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }' \
  '                if ($false) { continue }'
apply_mutant "M23 ループ内かを見ずに親を無制限に辿る" KILLED "$LIB" \
  '        if ($isLoop) {' '        if ($true) {'
apply_mutant "M24 S-6 違反を立てない" KILLED "$LIB" \
  '                $violations += "S-6:' '                $ignored = "S-6:'

echo
echo "=== S-7: DryRun 分岐のパリティ ==="
apply_mutant "M25 パリティ検査を丸ごと外す" KILLED "$LIB" \
  '    $violations += (Get-GissueDryRunParityViolations $rootAst)' \
  '    $violations += @()'
apply_mutant "M26 DryRun 分岐が無くても違反にしない" KILLED "$LIB" \
  '    if ($dryBlocks.Count -eq 0) {' '    if ($false) {'
# ⚠ ラベルに ` を使わない。二重引用符の中の ` はコマンド置換として実行され、
#   set -u のもとで "DryRun: unbound variable" になってハーネスが途中で止まる(実測)。
apply_mutant 'M27 -not $DryRun(実運転側)を DryRun 分岐と誤認する' KILLED "$LIB" \
  '                ($condText.IndexOf('"'"'-not'"'"', [System.StringComparison]::OrdinalIgnoreCase) -lt 0)) {' \
  '                ($true)) {'
apply_mutant "M28 アンカー 1 本(プリフライト判定)を一覧から落とす" KILLED "$LIB" \
  "    'Test-GissuePreflightShouldSpawn'
)" \
  "    'Test-GissuePreflightShouldSpawn-REMOVED'
)"
apply_mutant "M29 パリティ違反を立てない" KILLED "$LIB" \
  '            $v += "S-7: `-DryRun` 分岐が '"'"'$anchor'"'"' を呼んでいない' \
  '            $ignored = "S-7: `-DryRun` 分岐が '"'"'$anchor'"'"' を呼んでいない'

echo
echo "=== 実物(run-gissue-claude.ps1)への当て直し ==="
# ★ 穴1: 新しい LLM 起動点を足しても、先行ガードは全部 PASS のまま通る。
apply_mutant "M30 ゲートの外に新しいエンジン起動を増やす(未登録)" KILLED "$RUN" \
  '        $repoMaintStartedAtUtc = (Get-Date).ToUniversalTime()' \
  '        $extraJob = Start-Job -ScriptBlock { Invoke-GissueEngine -PromptText $p }
        $repoMaintStartedAtUtc = (Get-Date).ToUniversalTime()'
# ★ 穴2: ゲート呼び出しを前に残したまま、spawn をゲートの外へ出す。
apply_mutant "M31 REPO-MAINT の spawn をゲート分岐の外へ出す" KILLED "$RUN" \
  '        if (-not $preflightDecision.Spawn) {
            # 여기서 return 하면 이슈 순회(B/C)까지 건너뛴다 — 정비만 건너뛰고 아래로 계속 진행한다.' \
  '        if (-not $preflightDecisionRenamed.Spawn) {
            # 여기서 return 하면 이슈 순회(B/C)까지 건너뛴다 — 정비만 건너뛰고 아래로 계속 진행한다.'
apply_mutant "M32 REPO-MAINT の spawn を別名の変数で受ける(レジスタ両方向)" KILLED "$RUN" \
  '        $repoMaintJob = Start-Job -InitializationScript $repoMaintInit -ScriptBlock {' \
  '        $maintJobRenamed = Start-Job -InitializationScript $repoMaintInit -ScriptBlock {'
# ★ 穴3: per-issue の中断を「ログだけ」にする。
apply_mutant "M33 per-issue の break をログ出力に置き換える" KILLED "$RUN" \
  '                Write-Output "[BACKOFF-BREAK] 엔진 0 토큰 즉사(kind=$engineBlockedKind) — 이번 틱의 남은 $($issueQueue.Count - $qi)건은 기동하지 않는다: isn=$blockedList"
                break' \
  '                Write-Output "[BACKOFF-BREAK] 엔진 0 토큰 즉사(kind=$engineBlockedKind) — 이번 틱의 남은 $($issueQueue.Count - $qi)건은 기동하지 않는다: isn=$blockedList"'
apply_mutant "M34 DryRun 分岐からプリフライト判定を外す(DryRun が嘘をつく)" KILLED "$RUN" \
  '                $preflightDecision = Test-GissuePreflightShouldSpawn $preflightMeasure '"'"'REPO-MAINT'"'"'
                foreach ($pl in @($preflightDecision.LogLines)) { Write-Log $csn "[DryRun] $pl" }' \
  '                $preflightDecision = @{ Spawn = $true; Reason = '"'"'dryrun-always'"'"'; LogLines = @() }'
apply_mutant "M35 DryRun 分岐からバックオフ判定を外す" KILLED "$RUN" \
  "            \$tickBackoff = Test-GissueBackoffActive \$backoffStateFile ((Get-Date).ToUniversalTime()) 'REPO-MAINT'
            foreach (\$bl in @(\$tickBackoff.LogLines)) { Write-Log \$csn \"[DryRun] \$bl\" }" \
  '            $tickBackoff = @{ Active = $false; Kind = ""; LogLines = @() }'

echo
echo "=== 緑対照（赤くなってはいけない） ==="
apply_mutant "G01 レジスタの Why 文言を変える" GREEN "$LIB" \
  "Why  = 'CSN ごとのワーカージョブ。これ自体は LLM を呼ばず、下の 2 つのゲートをこの中に持つ。' }" \
  "Why  = 'CSN ごとのワーカージョブ(文言だけ差し替え)。' }"
apply_mutant "G02 判定に関与しないコメントを足す" GREEN "$LIB" \
  '# ── 本体 ───────────────────────────────────────────────────────────────────────' \
  '# ── 本体 ───────────────────────────────────────────────────────────────────────
# (緑対照) この行は判定に関与しない。'
apply_mutant "G03 レジスタの Layer 値を変える(層の注記は判定材料でない)" GREEN "$LIB" \
  "@{ Key = 'claude-cli|Test-GissueCjkContamination|qaPrompt'; Layer = 3; Gated = 'none';" \
  "@{ Key = 'claude-cli|Test-GissueCjkContamination|qaPrompt'; Layer = 9; Gated = 'none';"
apply_mutant "G04 러너の skip メッセージ文面を変える" GREEN "$RUN" \
  '            Write-Output "[REPO-MAINT] CSN $csn 정비 세션 미기동 (reason=$($preflightDecision.Reason)) — 이슈 순회로 진행"' \
  '            Write-Output "[REPO-MAINT] CSN $csn 정비 세션 미기동(스킵) — 이슈 순회로 진행"'
apply_mutant "G05 大小だけ違う綴りに変える(PowerShell では同じプロパティ)" GREEN "$RUN" \
  '        if (-not $preflightDecision.Spawn) {
            # 여기서 return 하면' \
  '        if (-not $preflightDecision.SPAWN) {
            # 여기서 return 하면'

echo
echo "================ NC 結果 ================"
echo "KILLED=$killed  SURVIVED=$survived  BROKEN=$broken  GREEN-OK=$green_ok  GREEN-BAD=$green_bad"
if [ "$survived" -gt 0 ] || [ "$broken" -gt 0 ] || [ "$green_bad" -gt 0 ]; then
  echo "判定: NG — SURVIVED/BROKEN/GREEN-BAD が 0 でなければ当て先が合っていない"
  exit 1
fi
echo "判定: OK — 全 mutant KILLED・緑対照も維持"
exit 0
