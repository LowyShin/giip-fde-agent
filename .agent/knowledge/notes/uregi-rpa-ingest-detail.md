# Uレジ RPA 売上取得 — 詳細設計 claim notes（要件7〜10）

> source: giip-3709 `[3/4] Uレジ売上データ自動取得（RPA方式）の設計` / CSN 70418
> spec: `.agent/specs/uregi-rpa-sales-ingest-detail-spec.md`
> 概観: giip-3710 `.agent/specs/uregi-rpa-sales-ingest-spec.md` / `.agent/knowledge/notes/uregi-rpa-ingest.md`

- **CLAIM-URG-101**（要件7）: `FcIngestRun.error_code` は 7 コード体系。`login_failed` は**リトライなし・即 poison**（同一アカウント＝企業コード単位を当 run で以降スキップ）でアカウントロックを原理的に防ぐ。
- **CLAIM-URG-102**（要件7）: `retry_offsets` 適用対象は `no_data`/`timeout`/`download_failed`（データ到着待ち・一過性）。非適用は `login_failed`（ロック回避）/`selector_not_found`/`store_resolve_failed`/`parse_failed`（UI/権限/データ仕様起因で再試行しても直らない）。同一 run 内の即時再ログインは全コードで禁止。
- **CLAIM-URG-103**（要件7）: 1 店舗の例外が他店舗を止めない根拠＝既存 per-store try/except（`fc_ingest._execute_run`）＋`release_stale` の 30 分 stale ロック自動解放。RPA は `UREGI_RPA_SESSION_TIMEOUT_MS` で 30 分枠内に収める。
- **CLAIM-URG-104**（要件7）: 失敗店舗は `/api/fc/ingest/summary` に `error_code`/`error_label` を**追加フィールド**で載せ、画面は**新クラスのみ**（CSS 不変 §31）で赤（要対応: login_failed/selector_not_found/store_resolve_failed/parse_failed）/黄（経過観察: no_data/timeout/download_failed）/緑を出し分ける。
- **CLAIM-URG-105**（要件8）: 暗号化は既存のみ再利用＝`env_settings_store.encrypt()/decrypt()`（Fernet / `ENV_SETTINGS_DB_ENC_KEY`）＋`FcServiceCredential.ciphertext`/`masked_fields`/`masked_tail`。**復号 API は新設しない**。復号はバッチメモリ内のみ、画面は `masked_tail` のみ表示。
- **CLAIM-URG-106**（要件8・RPA 固有）: スクショ/HTML ダンプのマスク規則＝(a) ログイン画面はスクショ採取全面禁止、(b) HTML ダンプは `input[type=password]`／コード入力欄の `value` を空置換、(c) ログは専用マスクフィルタ（資格情報・鍵・トークンを `***`）、(d) 保存先 `UREGI_RPA_DIAG_DIR`・保持 7 日（`UREGI_RPA_DIAG_RETENTION_DAYS`）。採取可はログイン成功後の画面のみ。
- **CLAIM-URG-107**（要件9）: URL/セレクタ/待機条件を単一ファイル `fc_uregi_locators.py`（実装フェーズ新規）へ集約。セレクタはラベル/role/テキストベース優先で脆い絶対パスを避ける。
- **CLAIM-URG-108**（要件9）: `owner.u-regi.com` ログイン後のリダイレクト先ホスト（`u04` 等）は**ハードコードせず** `page.url` から動的抽出し、以降は相対パスで組み立てる。`UREGI_SALES_EXPORT_PATH` 等は相対保持。
- **CLAIM-URG-109**（要件9）: ログイン成功後に毎回 Uレジバージョン（確認時 ver 8.14.13）を取得し `FcIngestRun.error_detail`/専用ログへ記録。`last_seen_version` と差異があれば**警告**（`.fc-ingest-version-warning`＋ログ WARN）を出し処理は継続。`last_seen_version` 更新は運用判断を挟む（自動で消さない）。
- **CLAIM-URG-110**（要件10）: CSV は UTF-16LE(BOM) を `utf-16`（not `utf-16le`）でデコード→`csv.reader(delimiter='\t')`→クォート自動解除。改行 CRLF/LF 両対応。
- **CLAIM-URG-111**（要件10）: 列は**1 行目ヘッダ名→インデックス辞書**でマッピング（固定インデックス禁止）。必須ヘッダ欠落は `parse_failed`。数値正規化＝カンマ除去（`"208,723"`→208723）／% 除去（`"24.02%"`→24.02）。
- **CLAIM-URG-112**（要件10）: 非日付行スキップは `当年日付` が `^\d{8}$`（YYYYMMDD）にマッチする行のみ採用（`TOTAL`/`MD35週` 等はスキップ）。全行スキップは `no_data`。
- **CLAIM-URG-113**（要件10）: 保存は `FcSalesDaily` の `(store_id, business_date, source='uregi')` ユニーク制約への UPSERT で冪等化。保存列は原則 `business_date`／`sales_amount`（当年実績）／`guest_count`（当年客数）の 3 列。
- **CLAIM-URG-114**（要件10・判断）: Uレジ CSV には**取引件数列が存在しない**ため `source='uregi'` 行の `tran_count` は **NULL**。客数での代替はしない（客数＝来店人数、取引件数＝会計回数で定義が異なる）。取引件数が業務要件化したら別 CSV/画面調査を別イシューで起票。
