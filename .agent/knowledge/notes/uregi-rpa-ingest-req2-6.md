# Uレジ RPA 売上取得 — 詳細設計 claim notes（要件2〜6）

> source: giip-3708 `[2/4] Uレジ売上データ自動取得（RPA方式）の設計` / CSN 70418
> spec: `.agent/specs/uregi-rpa-sales-ingest-req2-6-spec.md`
> 概観: giip-3710 `.agent/specs/uregi-rpa-sales-ingest-spec.md` / `.agent/knowledge/notes/uregi-rpa-ingest.md`
> 詳細(7-10): giip-3709 `.agent/specs/uregi-rpa-sales-ingest-detail-spec.md` / `.agent/knowledge/notes/uregi-rpa-ingest-detail.md`

- **CLAIM-URG-201**（要件2）: 店舗特定キーは `FcServiceCredential.external_store_id`（既存・Phase 1-A 未使用）に Uレジ店舗コード（例 `001`）を保持し、ログイン後の `code: name` 一覧と**文字列完全一致**で突合。前ゼロを落とす数値比較は禁止（`001`/`010`/`100` の誤爆防止）。全角/半角コロン両対応。
- **CLAIM-URG-202**（要件2）: フォールバックは全てフェイルファスト `store_resolve_failed`（**リトライなし**・`retry_offsets` 非適用, 3709 CLAIM-URG-102 と整合）。対象=候補0件/候補2件以上/`external_store_id` 未設定。`000` 等の管理者・集約店舗は `UREGI_STORE_EXCLUDE_CODES`/`UREGI_STORE_EXCLUDE_NAME_REGEX` で候補から除外。1 店舗の失敗は他店舗を止めない。
- **CLAIM-URG-203**（要件2）: 初回設定導線は新 API `GET /api/fc/uregi/stores?credential_id=` が除外後候補 `[{code,name}]` を返却（売上は取らない軽量フロー、ただしログイン1回を消費し予算に算入）。画面追加は新クラスのみ（CSS 不変 §31）。資格情報は返却・ログに出さない。
- **CLAIM-URG-204**（要件3）: 取得は単日でなく**遡及 N 日（既定 35＝月締め＋MD週最長35日を1範囲で吸収）を毎回まとめ取り**し `FcSalesDaily` を UPSERT 上書き。`N` は `UREGI_INGEST_LOOKBACK_DAYS`、`days`/`month_pair` 切替は `UREGI_INGEST_LOOKBACK_MODE`。1 店舗 1 ログイン・1 検索・1 CSV（ログイン回数削減がアカウントロック対策の根幹）。
- **CLAIM-URG-205**（要件3）: UPSERT キーは `FcSalesDaily (store_id, business_date, source='uregi')`（3709 CLAIM-URG-113 と整合）。遡及重複は上書きで吸収（締め後修正=後勝ち）。途中失敗は翌 run の遡及範囲が欠損日を再カバーし自己修復。
- **CLAIM-URG-206**（要件3）: `is_confirmed` は `business_date <= 当日 − UREGI_CONFIRM_LAG_DAYS`（既定7）で `true`、より新しければ速報 `false`。`false→true` は許可、`true→false` 巻き戻しは禁止（WARN ログのみ）。カラム未存在なら実装フェーズで追加 or 全行速報先行（本タスクは DDL 発行せず明文化のみ）。
- **CLAIM-URG-207**（要件4・判断）: 税集計は 3 案（(a)税抜固定片側/(b)税抜税込2回検索両方/(c)店舗ごと）比較の結果 **推奨 (a) 税抜固定・`sales_excl_tax` のみ**（`UREGI_TAX_MODE=excl`）に確定。(b) は検索2回で所要 **1.6〜1.7 倍**＋設定切替 UI 依存で脆弱、(c) は 70 店舗で保守過大。ログイン回数は全案 1 回で不変＝ロック直接リスクは同等だが (b) はセッション長延伸の別リスク。税込が要件化したら後続イシューでオプトイン (b) を検討。
- **CLAIM-URG-208**（要件4）: (a) 採用時の UPSERT は `sales_incl_tax` を書かず既存値温存（NULL 上書きしない）。将来、税率マスタ併用で `sales_incl_tax` を派生計算する余地を残す。
- **CLAIM-URG-209**（要件5）: 新規スケジューラを作らず既存 15 分ディスパッチャ＋`FcIngestSetting`（`ingest_time`/`retry_offsets`/`service_concurrency`/`spread_minutes`/`batch_size`）に相乗り。`ingest_time` を跨いだ最初のスロットで当日 run 生成、`spread_minutes` で店舗投入をジッタ分散。
- **CLAIM-URG-210**（要件6）: `service_concurrency` 推奨上限 **2〜3**。並列は**別アカウント間のみ**で、**同一アカウント（企業コード）は必ず直列（実質1）**＝並列ログインがロック誘発の最大要因。店舗間 `UREGI_RPA_INTER_STORE_DELAY_MS`（ジッタ）併用。
- **CLAIM-URG-211**（要件5-6・数値）: 総所要 ≒ ⌈70/concurrency⌉ ×(1店舗所要+店舗間ディレイ)。**楽観 約20分**（40秒×concurrency3→24段×50秒=1200秒）/**悲観 約88分**（120秒×concurrency2→35段×150秒=5250秒）。**アカウント集中（1アカ70店舗）時は実効並列1で 約175分**。アカウント分布が総所要を支配 → demo 実測を先行。
- **CLAIM-URG-212**（要件E）: 要件(2)店舗特定・(3)期間まとめ取り・(4)税抜固定の責務は**すべて `fetch_daily_sales` 内部に閉じ込め**、`verify_auth`/`fetch_daily_sales` シグネチャを維持、`fc_ingest._execute_run` の `uregi` 分岐変更を最小化。セレクタ/URL は `fc_uregi_locators.py`（3709 CLAIM-URG-107）へ集約。
- **CLAIM-URG-213**（要件F）: run-now `budget_seconds=30`（HTTP API 前提値）は RPA（1店舗40〜120秒以上）では必ず同期タイムアウト → **非同期キュー投入＋`job_id` 即時返却＋ポーリング**が必須（3710 §1-(11)/§3-2）。初回店舗候補 API（CLAIM-URG-203）も同期即応答を期待しない設計。
