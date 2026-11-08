#!/usr/bin/env bash
# [giip 4805] gissue スケジューラのガードを 1 本の入口から全部走らせる。
#
# ⚠ [giip 4806 訂正] 初版のこのヘッダは「このレポには CI が無い」と書いていたが、**それは誤りだった**。
#   `.github/workflows/repo-gates.yml` が PR と push(main) で `scripts/gissue/run-repo-gates.ps1`
#   を実行しており、そこが **test-*.ps1 を自動発見する正本ゲート**である(2026-10-24 結線)。
#   そのため初版は「判定の入口」を 2 本に増やしていた(= 同じ判定が 2 系統・rule 48 違反)。
#   訂正後の役割分担:
#     - test-*.ps1 / test-*.mjs の実行は **run-repo-gates.ps1 に委譲**する(ローカル = CI と同じコード)
#     - このスクリプトが足すのは、正本ゲートが拾わない **NC(当て直し)ハーネス `nc-*.sh`** だけ
#   新しいテストを足すときは `run-repo-gates.ps1` の `$ExpectedPs1TestCount` を上げる
#   （判定は `-lt` なので「多い」側は黙って通る = 床が下がったことに誰も気づかない）。
#
# 使い方:
#   bash scripts/gissue/tests/run-all.sh          # 正本ゲート全部（構文 + test-*.ps1/mjs + リンク）
#   bash scripts/gissue/tests/run-all.sh --nc     # 上記 + NC(当て直し)ハーネス（遅い・30分前後）
#
# 失敗したら非 0 で終わる。どれが落ちたかを最後にまとめて出す。
set -u
cd "$(dirname "$0")/../../.." || exit 1
WITH_NC=0
for a in "$@"; do [ "$a" = "--nc" ] && WITH_NC=1; done

fails=()
step() {
  local label="$1"; shift
  echo "──── $label"
  if "$@"; then echo "     OK"; else echo "     FAILED"; fails+=("$label"); fi
}

# [判定 1] 正本ゲート。構文+BOM と test-*.ps1 / test-*.mjs の全数、マークダウン相対リンクまで
#   ここが見る。**CI(repo-gates.yml)が呼ぶのと同一のスクリプト**なので、
#   「ワークトリーで green ≠ main で green」(KNOW-005)が起きない。
step '正本ゲート (run-repo-gates.ps1 — CI と同一)' \
  pwsh -NoProfile -ExecutionPolicy Bypass -File "$PWD/scripts/gissue/run-repo-gates.ps1" -RepoRoot "$PWD"

# [判定 2] NC(当て直し)。**本体 PASS だけでは当て先が合っている保証にならない**ので、
#   意図的な欠陥を入れてテストが必ず赤くなることを測る。正本ゲートは `test-*.ps1` だけを
#   自動発見するので、`nc-*.sh` はここでしか走らない（= このスクリプトが存在する唯一の理由）。
#   先行(4804/4805)は置き換えず併走させる。被覆は合併で測る。
if [ "$WITH_NC" = "1" ]; then
  step 'NC プリフライト (giip 4804・併走)'   bash "$PWD/scripts/gissue/tests/nc-preflight-target.sh"
  step 'NC バックオフ/[H] (giip 4805・併走)' bash "$PWD/scripts/gissue/tests/nc-engine-backoff.sh"
  step 'NC spawn ゲート順序 (giip 4806)'     bash "$PWD/scripts/gissue/tests/nc-spawn-gate-order.sh"
else
  echo "──── NC ハーネスは未実行（--nc で実行。commit 前には必ず 1 回通すこと）"
fi

echo
if [ "${#fails[@]}" -gt 0 ]; then
  echo "================ 失敗 ${#fails[@]} 件 ================"
  for f in "${fails[@]}"; do echo "  - $f"; done
  exit 1
fi
echo "================ 全ガード通過 ================"
