# Uレジ RPA 売上取得 — 基盤設計 claim notes（要件(1) 既存資産棚卸し＋実行方式選定）

> source: giip-3707 `[1/4] Uレジ売上データ自動取得（RPA方式）の設計` / CSN 70418
> spec: `.agent/specs/uregi-rpa-sales-ingest-req1-method-spec.md`
> 概観: giip-3710 `.agent/specs/uregi-rpa-sales-ingest-spec.md` / `.agent/knowledge/notes/uregi-rpa-ingest.md`
> 詳細(2-6): giip-3708 `.agent/specs/uregi-rpa-sales-ingest-req2-6-spec.md` / `.agent/knowledge/notes/uregi-rpa-ingest-req2-6.md`
> 詳細(7-10): giip-3709 `.agent/specs/uregi-rpa-sales-ingest-detail-spec.md` / `.agent/knowledge/notes/uregi-rpa-ingest-detail.md`

- **CLAIM-URG-001**（要件1・再利用方針）: RPA 化で新規に起こすのは `fetch_daily_sales` 内部（ブラウザ操作＋CSV パース）と取込ジョブ状態テーブル 1 本のみ。認証情報の暗号化保管・復号（`fc_credentials`＋`env_settings_store` Fernet）、売上 upsert（`fc_sales`）、設定読み取り（`env_settings_runtime`）、取込ディスパッチ（`fc_ingest`）、画面導線（`views_fc`）は**すべて既存再利用・新規独自実装を起こさない**。giip-3702/3703 で Uレジ向け暗号化保管の再利用は live dev 検証済み。
- **CLAIM-URG-002**（要件1・契約維持）: 既存 `fc_uregi.py` は HTTP API 前提プレースホルダ。RPA 方式はこの前提を覆すが、`verify_auth`/`fetch_daily_sales` の**シグネチャと戻り値の形（既存 upsert が期待する売上明細行表現）を維持**し、`fc_ingest._execute_run` の `uregi` 分岐変更を最小化する。
- **CLAIM-URG-003**（実行方式・2案比較）: Playwright 実行方式は 2 案比較。案 A=Python `playwright-python` を Django 管理コマンド内に閉じ込め（同一プロセス・純 Python）。案 B=既存 Node 版 Playwright（`scripts/package.json`・`session.ts`）を `subprocess` 起動し CSV パスを IPC で受領。
- **CLAIM-URG-004**（実行方式・推奨確定）: **推奨 = 案 A**。根拠=(1) Dockerfile 変更のみで成立（`pip install playwright`＋`playwright install --with-deps chromium`、Azure リソース変更不要・Python コンテナへの Node ランタイム同梱不要）、(2) 取込コードが 1 言語 1 リポに閉じ保守性高（要件9）、(3) `fetch_daily_sales` を純 Python のまま内部 RPA 化でき既存シグネチャ維持に素直、(4) 案 B の唯一の優位＝プロセス障害分離は要件11 の非同期ジョブ化で代替獲得可能。案 B は Chromium 同梱が slim/Alpine で困難等の場合の条件付きフォールバック。
- **CLAIM-URG-005**（Dockerfile 同梱可否）: smart-order Python イメージへの Chromium 同梱は**可能**。Debian/Ubuntu 系は `playwright install --with-deps chromium`（apt で共有ライブラリ一括解決）＋`PLAYWRIGHT_BROWSERS_PATH` 固定。slim/Alpine/musl 系は `mcr.microsoft.com/playwright/python` 公式イメージを multi-stage ベース採用。いずれも **Dockerfile 変更のみで成立・Azure リソース変更不要**。懸念=イメージサイズ数百 MB 増・ビルド時間増・コールドスタート。既存 Node Playwright があれば Chromium 版を揃える。本タスクでは Dockerfile を変更しない（可否論述のみ）。
- **CLAIM-URG-006**（run-now 非同期化・方式非依存）: `budget_seconds=30` は HTTP API 前提値。RPA は 1 店舗 40〜120 秒以上（3708 CLAIM-URG-211）で**案 A/B いずれでも同期実行は必ずタイムアウト**。対処=run-now は `job_id` 即時返却＋ポーリング（3710 §1-(11)/§3-2、3708 CLAIM-URG-213）。この非同期化は案 A 採用時に案 B のプロセス障害分離利点を代替獲得する手段でもある。
- **CLAIM-URG-007**（アカウントロック・上位制約）: アカウントロックは方式選定より上位の固定前提。ログイン失敗リトライなし・1 店舗 1 ログインで月範囲まとめ取り・並列は別アカウント間のみ（同一企業コードは直列）。案 A/B どちらでも同一適用（3710 §5-2、3708 CLAIM-URG-210）。
