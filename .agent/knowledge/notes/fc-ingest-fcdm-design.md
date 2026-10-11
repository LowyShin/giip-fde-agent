# FC 連携・夜間取込画面（/fc/ingest/）デザイン統一 知識ノート

> カパシ K-Layer: FC本部画面のデザイントークン整合で観察された事実
> すべての claim は source-linked。削除禁止、invalidated_at でのみ無効化。
> 由来: giip-3727/3728/3729（[1-3/3] /fc/ingest/ レイアウトをFC本部デザインへ統一）

---

## FC画面デザイントークンの不整合

CLAIM-FCING-001: FC配下の自作デザイン画面（`/fc/ingest/` の緑 `#14532d`/`#15803d`・角丸カード）は、他のFC本部画面（`/fc/hq/settings/` 等）が使うFC本部トークン（`.fcdm` ベージュ・角なし・インク `#2B221C`）と視覚的に不整合になる。見た目統一は「同じ値のトークンを自画面の新クラスに写す」方式で解消でき、`.fcdm` 配下へDOMを移してトークンを継承させる案は `.fcdm *` のリセットが既存 `.fcing__*` と衝突し二重適用を起こすため不可。
- **evidence**: giip-3727 実装で緑トークン除去（dev配信 `fc_ingest.html` に旧緑 0 件・`#2B221C` 適用を機械確認）。`.fcdm` 配下移設案は giip-3727 コミット本文で Rejected 記録。
- **source**: `LowyShin/vgt-smart-order-system` dev `9ae1d945` `app/templates/fc_ingest.html`、`app/static/css/screens/fc_dash.css`（`.fcdm` トークン定義）
- **observed_at**: 20261011
- **invalidated_at**: null
- **confidence**: high

CLAIM-FCING-002: FC画面のCSS統一は新規 `app/static/css/screens/*.css` ファイルでは実現できない。`check_fc_off_surface.py` の `SHARED_DENY` が `^app/static/` 配下を**新規ファイルでも**共有アセット扱いにして FCトグルOFFサーフェスのバイト差分を検出し exit 1 になるため。描画ビューが `@fc_feature_required` で閉じている画面は、変更を当該テンプレート自身の `{% block css %}`（画面スコープ）内の新クラスに閉じ込めれば、共有アセット（`base.html`・`^app/static/`）をバイト不変に保てる。
- **evidence**: 当初計画の `fc_ingest_fcdm.css` 新規作成を OFFサーフェス検査回避のため取り下げ、`fc_ingest.html` の block css へ新クラス `.fcingl-*` を配置（giip-3727 コミット本文 Rejected(a)）。dev で `base.html`・`fc_ingest.css` が parent→dev バイト同一を確認。
- **source**: `LowyShin/vgt-smart-order-system` dev `9ae1d945`、giip-3727 コミットメッセージ
- **observed_at**: 20261011
- **invalidated_at**: null
- **confidence**: high

---

## PCシェルと本文の見出し二重化

CLAIM-FCING-003: PCシェル `fcPcPage.adopt('main.fcing')`（`app/static/js/screens/fc_pc_page.js`）は 900px 以上で上帯 `.bar h1` に画面見出しを出す。本文テンプレートにも同一文言の `h1` があると、900px 以上で見出しが二重化する。解消は「本文 h1 を `@media (min-width:900px)` で非表示」にする（`adopt()` の差し替え境界も同じ 900px なので表示がズレない。900px 未満はシェル上帯が無いため本文 h1 が唯一の見出しとして残る）。
- **evidence**: giip-3727 実装で `fc_ingest.html` に 900px メディアクエリ（本文 h1 非表示）を追加、dev 配信テンプレートで 900px 指定を機械確認。
- **source**: `LowyShin/vgt-smart-order-system` dev `9ae1d945` `app/templates/fc_ingest.html`、`app/static/js/screens/fc_pc_page.js`
- **observed_at**: 20261011
- **invalidated_at**: null
- **confidence**: high

---

## FCトグルOFFバイト不変の検証代替

CLAIM-FCING-004: `check_fc_off_surface.py` が当該デプロイ・対象リポのいずれにも存在しない場合、FCトグルOFFサーフェスのバイト不変は「共有アセット（`base.html`・`^app/static/`）と `views_fc.py`/`urls.py` の blob SHA が parent→head で同一」かつ「変更ファイルが `@fc_feature_required` ゲート下のテンプレートのみ」を機械確認することで構造的に代替担保できる（CLAIM-5219 の前提を満たす）。
- **evidence**: giip-3729 検証で parent `0238e41f`→dev `9ae1d945` の `base.html`/`fc_ingest.css`/`views_fc.py`/`urls.py` が blob SHA 同一、変更は `fc_ingest.html` 1 本のみを GitHub contents API で確認。
- **source**: giip-3729 検証セッション 20261011、`LowyShin/vgt-smart-order-system` commits API
- **observed_at**: 20261011
- **invalidated_at**: null
- **confidence**: mid
