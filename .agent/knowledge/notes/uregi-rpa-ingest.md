# Uレジ RPA 売上取得 — claim notes

> source: giip-3710 `[4/4] Uレジ売上データ自動取得（RPA方式）の設計` / CSN 70418
> spec: `.agent/specs/uregi-rpa-sales-ingest-spec.md`

- **CLAIM-URG-001**: Uレジは公開 HTTP API を持たない。売上実績は管理画面からの CSV エクスポートでのみ取得でき、RPA（Playwright ブラウザ自動操作）が唯一の自動取得手段。
- **CLAIM-URG-002**: Uレジ売上実績 CSV の文字コードは **UTF-16LE**、区切りは **TAB**。デコード時は BOM（0xFFFE）有無と改行コード（CRLF/LF）の双方に対応する必要がある。
- **CLAIM-URG-003**: 既存 `fc_uregi.py` の `verify_auth` / `fetch_daily_sales` は HTTP API 前提のプレースホルダ。RPA 化は**シグネチャを維持し内部実装のみ差し替える**方針とし、`fc_ingest._execute_run` の `uregi` 分岐変更を最小化する。
- **CLAIM-URG-004**: 最大リスクはアカウントロック。固定方針は (a) ログイン失敗時リトライ禁止、(b) 並列数上限（同一アカウントは直列）、(c) 1 店舗 1 回ログイン＋月範囲まとめ取りでログイン回数削減。
- **CLAIM-URG-005**: 既存 fc_ingest 拡張点 = `_execute_run` の `uregi` 分岐（夜間バッチ相乗り、70 店舗をアカウント単位で直列）と `/api/fc/ingest/run-now`（`run_now_for_schema`）の手動実行経路。
- **CLAIM-URG-006**: `run-now` の `budget_seconds=30` は HTTP API 前提値。RPA は 1 店舗数十秒〜数分かかり同期実行では必ずタイムアウトするため、**非同期キュー投入＋ポーリング表示**（job_id 即時返却＋状況 API）が必須。
- **CLAIM-URG-007**: 認証情報は既存 `fc_credentials` ＋ `env_settings_store`（暗号化）を再利用。追加設定値は §0-c により DB（`env_settings_shared_value`）＋`env_settings_runtime` 経由（ARM 直書き例外は DB 接続系 5 変数のみ）。
- **CLAIM-URG-008**: 検証は demo テナント `vtsmodemovegetrade` のみ。`vtsmomaruei` は読み取り専用・一切触らない。
