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

> source 追補: giip-3748/3749/3750 `Uレジ連携からAPI前提の表示・設定を削除する` / CSN 70418

- **CLAIM-URG-009**: 取込方法の選択肢は per-service（`fc_credentials.MODES_BY_SERVICE`）で定義し、Uレジは `('manual',)` のみ＝「API連携（自動取込）」を提供しない。旧データで `ingest_mode='api'` の行が残っていても `normalize_mode(spec, mode)` が `manual` に寄せて読む（rule 42 前方互換）。`MODE_LABELS` の `'api'` ラベル自体は旧行の表示のために残すが、選択肢としては出さない。
- **CLAIM-URG-010**: 未設定 env（`UREGI_API_BASE_URL`）起因の恒久エラーを UI に出さない設計原則。設定すべき値が存在しない原因でユーザーが自力で消せない永久的な `auth_error`（連携設定画面の赤い「取込エラー」バッジ）を生まない。接続確認は `normalize_mode` が `manual` と判定した店舗では `verify_auth()` を呼ばず `unsupported`（確認を行わない）で返し、旧 `api` 行で接続テストを押しても `auth_error` を DB に再生産しない。
