#!/usr/bin/env bash
# [giip 4804] test-preflight-target.ps1 の NC（当て直し / mutation）ハーネス
#
# 用途: 「本体 PASS」だけでは当て先が合っている保証にならない（先行ガードが PASS・NC 宣言どおりでも
#   当て直すと新 mutant の大半が生き残る型が繰り返し出ている）。ここでは lib/preflight-target.ps1 と
#   run-gissue-claude.ps1 に意図的な欠陥(mutant)を1件ずつ入れ、テストが必ず赤になる(KILLED)ことを測る。
#   加えて「赤になってはいけない」緑対照(GREEN)も混ぜ、テストが何にでも赤くなる代物でないことを示す。
#
# 処理: 対象ファイルを .ncbak に退避 → mutant 適用 → pwsh でテスト実行 → 復元。
#   復元は trap で必ず行う。書き込みは対象2ファイルとその .ncbak だけ。
# 消費先: giip-4804 の結果レポート（合併被覆の根拠）。
#
# 実行: bash scripts/gissue/tests/nc-preflight-target.sh
set -u
cd "$(dirname "$0")/../../.." || exit 1
LIB=scripts/gissue/lib/preflight-target.ps1
RUN=scripts/gissue/run-gissue-claude.ps1
TEST=scripts/gissue/tests/test-preflight-target.ps1

restore() { for f in "$LIB" "$RUN"; do [ -f "$f.ncbak" ] && mv -f "$f.ncbak" "$f"; done; }
trap restore EXIT INT TERM

run_test() { pwsh -NoProfile -ExecutionPolicy Bypass -File "$TEST" >/tmp/_nc_out.txt 2>&1; echo $?; }

# 期待値つき mutant 適用。$1=ラベル $2=KILLED|GREEN $3=ファイル $4=探す文字列 $5=置換文字列
killed=0; survived=0; broken=0; green_ok=0; green_bad=0
apply_mutant() {
  local label="$1" expect="$2" file="$3" from="$4" to="$5"
  cp -f "$file" "$file.ncbak"
  if ! FROM="$from" TO="$to" python3 -I - "$file" <<'PY'
import os,sys,io
p=sys.argv[1]
raw=open(p,'rb').read()
bom = raw.startswith(b'\xef\xbb\xbf')
s=raw.decode('utf-8-sig')
f=os.environ['FROM']; t=os.environ['TO']
n=s.count(f)
if n != 1:
    sys.stderr.write('ANCHOR_COUNT=%d\n' % n); sys.exit(3)
s=s.replace(f,t)
out=s.encode('utf-8')
open(p,'wb').write((b'\xef\xbb\xbf' if bom else b'')+out)
PY
  then
    echo "[BROKEN] $label — mutant のアンカーが一意に当たらない（当て先ずれ: 先に直すべきはテストでなくこの行）"
    broken=$((broken+1)); mv -f "$file.ncbak" "$file"; return
  fi
  local rc; rc=$(run_test)
  mv -f "$file.ncbak" "$file"
  if [ "$expect" = "KILLED" ]; then
    if [ "$rc" != "0" ]; then
      echo "[KILLED]   $label  ($(grep -c '^\[FAIL\]' /tmp/_nc_out.txt) 件の FAIL)"
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
      echo "[GREEN-BAD] $label ← 無害な変更で赤くなる（過敏なテスト）: $(grep '^\[FAIL\]' /tmp/_nc_out.txt | head -3)"
      green_bad=$((green_bad+1))
    fi
  fi
}

echo "=== 前提: mutant なしで本体が緑であること ==="
rc0=$(run_test)
if [ "$rc0" != "0" ]; then echo "[ABORT] mutant 適用前からテストが赤い"; grep '^\[FAIL\]' /tmp/_nc_out.txt | head; exit 1; fi
echo "[BASE-OK] $(grep -c '^\[PASS\]' /tmp/_nc_out.txt) PASS / 0 FAIL"
echo

echo "=== 判定契約 P-1〜P-6 ==="
apply_mutant "M01 SKIP 行の固定フォーマットを崩す" KILLED "$LIB" \
  "'SKIP reason=no-target job={0} count=0'" "'SKIP job={0}'"
apply_mutant "M02 0件だが判定不能のとき skip してしまう(P-1)" KILLED "$LIB" \
  '    if ($Measure.Unknown) {
        # P-1/P-2: 0 に見えても判定不能が混ざっていれば skip しない。必ず理由を立てる。' \
  '    if ($false) {
        # P-1/P-2: 0 に見えても判定不能が混ざっていれば skip しない。必ず理由を立てる。'
apply_mutant "M03 測り手全滅を 0件と読む(P-4)" KILLED "$LIB" \
  '    if ($m.PortsResolved -le 0) {' '    if ($false) {'
apply_mutant "M04 ポートの契約違反(生配列)を 0件と読む(P-6)" KILLED "$LIB" \
  '        if (-not (Test-GissuePreflightResultShape $raw)) {' '        if ($false) {'
apply_mutant "M05 ポート例外を Unknown でなく 0件にする(P-1)" KILLED "$LIB" \
  '        return New-GissuePreflightUnknown "$Label 例外: $($_.Exception.Message)"' \
  '        return New-GissuePreflightCount 0'
apply_mutant "M06 port 未指定を 0件と読む(P-4)" KILLED "$LIB" \
  '    if ($null -eq $Port) { return New-GissuePreflightUnknown "port 未指定($Label)" }' \
  '    if ($null -eq $Port) { return New-GissuePreflightCount 0 }'
apply_mutant "M07 判定不能時の WARN を出さない(P-2)" KILLED "$LIB" \
  '        $lines += "[PREFLIGHT][WARN] job=$JobName 対象0件に見えるが判定不能あり' \
  '        $lines += "[PREFLIGHT] job=$JobName 対象0件に見えるが判定不能あり'
apply_mutant "M08 対象ありで一部判定不能のときの WARN を落とす" KILLED "$LIB" \
  '        if ($Measure.Unknown) {
            $lines += "[PREFLIGHT][WARN] job=$JobName 一部判定不能' \
  '        if ($false) {
            $lines += "[PREFLIGHT][WARN] job=$JobName 一部判定不能'
apply_mutant "M09 Measure が null でも 0件扱いで skip する" KILLED "$LIB" \
  '            Reason   = '"'"'preflight-unknown'"'"'
            LogLines = @("[PREFLIGHT][WARN] job=$JobName 判定結果が null' \
  '            Reason   = '"'"'no-target'"'"'
            LogLines = @("[PREFLIGHT] job=$JobName 判定結果が null'

echo
echo "=== 件数の数え方 ==="
apply_mutant "M10 [H] の件数を Total に足さない" KILLED "$LIB" \
  '    $m.Total = $m.Conflicting + $m.FailingCi + $m.OrphanStash + $m.RecentComment' \
  '    $m.Total = $m.Conflicting + $m.FailingCi + $m.OrphanStash'
apply_mutant "M11 レポ単位の件数を加算しない" KILLED "$LIB" \
  '                $m."$($spec.Field)" = $m."$($spec.Field)" + $r.Count' \
  '                $m."$($spec.Field)" = $m."$($spec.Field)" + 0'
apply_mutant "M12 worktree 重複排除をやめる(二重計上)" KILLED "$LIB" \
  '        if ($seen.ContainsKey($key)) { continue }' '        if ($false) { continue }'

echo
echo "=== [0] conflict 分類 ==="
apply_mutant "M13 mergeable=UNKNOWN を衝突なしと断定する" KILLED "$LIB" \
  "        if (\$mg -eq 'UNKNOWN' -or -not \$mg) {" '        if ($false) {'
apply_mutant "M14 CONFLICTING 以外も衝突に数える" KILLED "$LIB" \
  "        if (\$mg -eq 'CONFLICTING') { \$hit++ }" '        $hit++'

echo
echo "=== [E] CI 失敗分類 ==="
apply_mutant "M15 TIMED_OUT を失敗集合から落とす" KILLED "$LIB" \
  "@('FAILURE', 'TIMED_OUT', 'CANCELLED', 'STARTUP_FAILURE', 'ACTION_REQUIRED')" \
  "@('FAILURE', 'CANCELLED', 'STARTUP_FAILURE', 'ACTION_REQUIRED')"
apply_mutant "M16 STARTUP_FAILURE を失敗集合から落とす" KILLED "$LIB" \
  "'FAILURE', 'TIMED_OUT', 'CANCELLED', 'STARTUP_FAILURE'" \
  "'FAILURE', 'TIMED_OUT', 'CANCELLED'"
apply_mutant "M17 state=ERROR を見ない" KILLED "$LIB" \
  "\$script:GissuePreflightCiFailStates      = @('FAILURE', 'ERROR')" \
  "\$script:GissuePreflightCiFailStates      = @('FAILURE')"
apply_mutant "M18 PENDING も失敗に数える" KILLED "$LIB" \
  "\$script:GissuePreflightCiFailStates      = @('FAILURE', 'ERROR')" \
  "\$script:GissuePreflightCiFailStates      = @('FAILURE', 'ERROR', 'PENDING')"
# M19 は「無害な変更」なので緑対照側。PowerShell の -contains は既定で大文字小文字を区別しない
#   ため、ToUpperInvariant は二重の防御であって振る舞いを変えない = 構造上殺せない mutant。
#   殺せないことを隠さずここに残す（削除の根拠にはしない）。
apply_mutant "M19 大文字化をやめる(PowerShell -contains は元から大小無視 = 無害)" GREEN "$LIB" \
  '            $concl = "$($c.conclusion)".ToUpperInvariant()' \
  '            $concl = "$($c.conclusion)"'
apply_mutant "M20 PR 単位 break をやめてチェック単位で数える" KILLED "$LIB" \
  '                $hit++
                break
            }
        }
    }
    return New-GissuePreflightCount $hit
}

# [F] auto-unblock stash 判定' \
  '                $hit++
            }
        }
    }
    return New-GissuePreflightCount $hit
}

# [F] auto-unblock stash 判定'

echo
echo "=== [F] stash 分類 ==="
apply_mutant "M21 先頭一致でなく含有で判定する" KILLED "$LIB" \
  "        if (\$msg.StartsWith('auto-unblock ')) { \$hit++ }" \
  "        if (\$msg.Contains('auto-unblock')) { \$hit++ }"
apply_mutant "M22 末尾の空白を落として前方一致を緩める" KILLED "$LIB" \
  "        if (\$msg.StartsWith('auto-unblock ')) { \$hit++ }" \
  "        if (\$msg.StartsWith('auto-unblock')) { \$hit++ }"
apply_mutant "M23 'On <branch>:' の剥がしをやめる" KILLED "$LIB" \
  "        if (\$msg -match '^(?:On|WIP on)\s+\S+:\s*(.*)\$') { \$msg = \$Matches[1].Trim() }" \
  "        if (\$false) { \$msg = \$Matches[1].Trim() }"

apply_mutant "M28 Detail のレポ名ラベルを変える(証跡が読めなくなる)" KILLED "$LIB" \
  "Label = \"[0]conflict@\$repo\"" "Label = \"[0]CONFLICT@\$repo\""
apply_mutant "M29 0件でも内訳行を残す規約を外す(測った/測っていないが区別不能になる)" KILLED "$LIB" \
  '    $m.Detail = @("repos=$(@($repos).Count)",' '    $m.Detail = @(' 

echo
echo "=== 러너 배선 ==="
apply_mutant "M24 preflight lib の닷소싱을 지운다" KILLED "$RUN" \
  "        . (Join-Path \$root 'lib/preflight-target.ps1')" \
  "        # (removed by NC)"
apply_mutant "M25 Spawn=false でも Start-Job に進む" KILLED "$RUN" \
  '        if (-not $preflightDecision.Spawn) {' '        if ($false) {'
apply_mutant "M26 주체크아웃 선별(worktree 제외)을 거치지 않는다" KILLED "$RUN" \
  '        $preflightRepos = @(Select-GissuePreflightPrimaryRepos (Get-GissueGitRepoPaths $workdir))' \
  '        $preflightRepos = @(Get-GissueGitRepoPaths $workdir)'
apply_mutant "M30 프리플라이트의 예외 폴백(try 진입)을 없앤다" KILLED "$RUN" \
  '        $preflightMeasure = $null
        $prevEapPf = $ErrorActionPreference' \
  '        $preflightMeasure = $null
        $prevEapPfRemovedByNC = $ErrorActionPreference'
apply_mutant "M31 ErrorActionPreference 를 원복하지 않는다" KILLED "$RUN" \
  '        } finally {
            $ErrorActionPreference = $prevEapPf
        }' \
  '        } finally {
            $null = $prevEapPf
        }'
apply_mutant "M27 Measure 를 거치지 않고 판정한다" KILLED "$RUN" \
  '        $preflightMeasure = Measure-GissueRepoMaintTargets $preflightRepos @{' \
  '        $preflightMeasure = $null; $unusedPorts = @{'

echo
echo "=== 緑対照（赤くなってはいけない変更） ==="
apply_mutant "G01 lib のコメント文言を変える" GREEN "$LIB" \
  '# 用途' '# 用途（NC 緑対照で文言だけ変えた）'
apply_mutant "G03 러너 로그 문구만 바꾼다" GREEN "$RUN" \
  '이슈 순회로 진행"' '이슈 순회로 계속 진행"'

echo
echo "================ NC 結果 ================"
echo "KILLED   : $killed"
echo "SURVIVED : $survived"
echo "BROKEN   : $broken   (mutant のアンカーが一意に当たらなかった = 当て先ずれ)"
echo "GREEN-OK : $green_ok"
echo "GREEN-BAD: $green_bad"
total=$((killed+survived))
echo "kill rate: $killed/$total"
if [ "$survived" -gt 0 ] || [ "$broken" -gt 0 ] || [ "$green_bad" -gt 0 ]; then exit 1; fi
echo "NC: 全 mutant KILLED・緑対照も緑"
