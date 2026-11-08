#!/usr/bin/env bash
# [giip 4805] gissue スケジューラのガードを 1 本の入口から全部走らせる。
#
# なぜ必要か: このレポには pre-push フックも CI も無い(2026-11-08 時点で `core.hooksPath` 未設定・
#   .githooks なし・テストを参照する workflow なし)。テストと NC ハーネスは書いてあるのに
#   **誰も自動で走らせない**ので、壊れても誰も気づかない = 「測り手不在で永久に緑」の process 版。
#   フック基盤そのものを作るのは本タスクの範囲外(giip 4806 の判断事項)なので、ここでは
#   「1 コマンドで全部走る」入口だけを用意する。commit/push 前に手で叩ける。
#
# 使い方:
#   bash scripts/gissue/tests/run-all.sh          # 構文 + 単体テスト（速い・数十秒）
#   bash scripts/gissue/tests/run-all.sh --nc     # 上記 + NC(当て直し)ハーネス（遅い・20分前後）
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

# [判定 1] 構文 + BOM。powershell -File は構文エラーでも 0 を返すことがあるので先に止める(giip #2429)。
step '構文+BOM (check-ps1-parse.ps1)' \
  pwsh -NoProfile -File "$PWD/scripts/gissue/check-ps1-parse.ps1" \
    "$PWD/scripts/gissue/run-gissue-claude.ps1" \
    "$PWD/scripts/gissue/lib/preflight-target.ps1" \
    "$PWD/scripts/gissue/lib/engine-backoff.ps1" \
    "$PWD/scripts/gissue/lib/h-recheck-watermark.ps1"

# [判定 2] 単体テスト。各ファイルは「러너への配線が実在するか」まで見る(書いても呼ばれて
#   いなければ意味が無いため)。
step 'プリフライト (giip 4804)' pwsh -NoProfile -ExecutionPolicy Bypass -File "$PWD/scripts/gissue/tests/test-preflight-target.ps1"
step 'バックオフ (giip 4805)'   pwsh -NoProfile -ExecutionPolicy Bypass -File "$PWD/scripts/gissue/tests/test-engine-backoff.ps1"
step '[H] 高水位マーク (giip 4805)' pwsh -NoProfile -ExecutionPolicy Bypass -File "$PWD/scripts/gissue/tests/test-h-recheck-watermark.ps1"

# [判定 3] NC(当て直し)。**本体 PASS だけでは当て先が合っている保証にならない**ので、
#   意図的な欠陥を入れてテストが必ず赤くなることを測る。先行(4804)は置き換えず併走させる。
if [ "$WITH_NC" = "1" ]; then
  step 'NC プリフライト (giip 4804・併走)' bash "$PWD/scripts/gissue/tests/nc-preflight-target.sh"
  step 'NC バックオフ/[H] (giip 4805)'     bash "$PWD/scripts/gissue/tests/nc-engine-backoff.sh"
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
