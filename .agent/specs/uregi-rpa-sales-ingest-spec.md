<!--
taskId: giip-3710
title: [4/4] Uレジ売上データ自動取得（RPA方式）の設計
csn: 70418
status: DESIGN-ONLY（実装・アプリコード変更は本タスク範囲外）
-->

# Uレジ売上データ自動取得（RPA方式）設計書

- **taskId**: `giip-3710`
- **GIIP issue**: isn=3710 `[4/4] Uレジ売上データ自動取得（RPA方式）の設計`
- **CSN**: 70418
- **位置づけ**: FC連携サブイシューチェーンの 4/4（設計フェーズ）。本書が本タスクの唯一の成果物。
- **成果物スコープ**: 設計のみ。アプリケーションコードの実装・変更・コミットは行わない。本書・`.agent/tasks/giip-3710.md`・`.agent/knowledge/notes/` の claim のみを commit/push 対象とする。
- **作業ブランチ**: 本レポ（giip-fde-agent）では feature ブランチ → PR。設計書が言及する vgt-smart-order-system 側の実装は dev-first（作業ブランチ dev、stg/main への PR は作らない）を前提に記述する。

---

## 0. 背景と前提

Uレジ（POSレジ SaaS）は売上実績の**公開 HTTP API を持たない**。既存の `fc_uregi.py` は「HTTP API で取得する」前提のプレースホルダ（`verify_auth` / `fetch_daily_sales`）として実装されている。本設計はこの前提を覆し、**Playwright によるブラウザ自動操作（RPA）**で、Uレジ管理画面から売上実績CSV（**UTF-16LE / TAB 区切り**）を**日次**で取得する方式を定義する。

対象は **70 店舗**。取得処理は既存の `fc_ingest` 夜間バッチに**相乗り**させる（新規スケジューラは作らない）。

### 0-1. 絶対制約（本設計が従う前提）

- **実在の認証情報を一切含めない**。企業コード／担当者コード／パスワードは本書・コード・ログ・コミットのいずれでもプレースホルダ表記のみ。
- **`vtsmomaruei` は読み取り専用・絶対に触らない**。検証前提は demo テナント `vtsmodemovegetrade` のみ。
- **環境変数・App Settings・Azure リソースの変更は本タスクでは行わない**。必要な変数は「名前と用途」のみ列挙する。
- **§0-c（DB 管理の設定値）**: 追加が必要な設定値は ARM 直書きではなく DB（`env_settings_shared_value`）管理＋`env_settings_runtime` 経由読み取りを前提に設計する。例外は `DB_HOST` / `DB_NAME` / `DB_USER` / `DB_PASSWORD` / `ENV_SETTINGS_DB_ENC_KEY` の 5 つのみ。
- **CSS 不変原則（§31）**: 「今すぐ取込」「取込状況」画面への表示追加を設計する場合も、既存 CSS の変更は禁止。**新クラス名での追加のみ**。
- **既存シグネチャ維持**: `verify_auth` / `fetch_daily_sales` のシグネチャを維持し、**内部実装だけ RPA に差し替える**。`fc_ingest._execute_run` の `uregi` 分岐の変更を最小化する。

### 0-2. 本設計で言及するのみ・本タスクでは一切変更しないファイル

| ファイル | 役割 | 本設計での扱い |
|---|---|---|
| `vgt-smart-order-system/app/main_system/fc_uregi.py` | API 前提のプレースホルダ | **RPA 差替対象**（内部実装のみ。シグネチャ維持） |
| `vgt-smart-order-system/app/main_system/fc_ingest.py` | 取込ディスパッチャ（`_execute_run` の `uregi` 分岐） | 分岐の呼び出し規約を最小変更 |
| `vgt-smart-order-system/app/main_system/fc_models.py` | 取込関連 ORM モデル | ジョブ状態テーブル追加箇所 |
| `vgt-smart-order-system/app/main_system/fc_credentials.py` | FC 認証情報の暗号化保管 | 再利用（Uレジ資格情報を同機構で保管） |
| `vgt-smart-order-system/app/main_system/fc_sales.py` | 売上明細の upsert | 既存 upsert を再利用 |
| `vgt-smart-order-system/app/main_system/views_fc.py` | 画面・API エンドポイント | run-now の store_id 対応／状況ポーリング API 追加箇所 |
| `vgt-smart-order-system/app/main_system/env_settings_runtime.py` | 設定値の DB 読み取り | 再利用（新規環境変数の読み取り元） |
| `vgt-vegetrade-auth-api/app/services/env_settings_store.py` | 暗号化機構の再利用元 | 再利用 |
| `tools/demo-autopilot/src/lib/session.ts` | Playwright 既存資産（セッション管理） | 設計の参考・流用検討 |
| `scripts/package.json` | Playwright 依存の既存宣言 | ブラウザ同梱検討の参考 |
| smart-order の `Dockerfile` | コンテナビルド定義 | ブラウザバイナリ同梱の可否を**論じるのみ** |

> 注記: 本レポ（giip-fde-agent, csn 70418 運用）には上記ファイルは存在しない。上表は姉妹 `vgt-smart-order-system` レポ所管であり、本設計はイシュー本文に記載されたインターフェース名（`run_now_for_schema` / `_execute_run` / `verify_auth` / `fetch_daily_sales` / `budget_seconds=30`）を前提に記述している。実装フェーズで実ファイルのシグネチャと差異があれば、シグネチャ維持の原則に従って実ファイル側を正とする。

---

## 1. 要件(1)〜(11) への回答

> 本イシュー本文で明示的に carryover されている要件は (11) のみ。(1)〜(10) はチェーン 1/4〜3/4 およびイシュー本文の記述（CSV 仕様・まとめ取り・アカウントロック・コンテナ同梱・70 店舗・既存機構再利用等）から、本設計が答えるべき要件として再構成したものである。実装フェーズで原要件定義（1/4〜3/4 の成果物）と照合すること。

### (1) 認証方式（ログイン自動化）
Playwright でログイン画面を開き、復号した**企業コード／担当者コード／パスワード**を入力して送信する。ログイン成否はログイン後ランディング要素（売上メニュー等の存在）で判定する。**ログイン失敗時はリトライしない**（§8 アカウントロック対策）。

### (2) 売上CSVの取得経路（画面操作フロー）
ログイン → 売上実績メニュー → 期間指定 → CSV エクスポート操作 → ダウンロード完了待機（Playwright の `download` イベント）→ 一時ディレクトリへ保存 → ログアウト。セレクタは一箇所に集約し DOM 変更耐性を確保する（§8）。

### (3) CSVフォーマット（UTF-16LE/TAB）のパースと取込
ダウンロードファイルを **UTF-16LE** でデコードし、**TAB** 区切りでパースする。ヘッダ行から列位置を解決（固定インデックスに依存しない）し、内部の売上明細スキーマへマッピングして `fc_sales.py` の既存 upsert に渡す。BOM（`0xFFFE`）有無の両対応、改行コード（CRLF/LF）両対応。

### (4) 取得対象期間とまとめ取り戦略
日次バッチだが、**1 店舗 1 回ログインで月範囲（当月＋前日分の補完）をまとめ取り**する設計とし、ログイン回数を最小化する（アカウントロック対策に直結）。取得済み期間は冪等 upsert（§7）で重複を排除する。

### (5) 70店舗分のバッチ組み込み（fc_ingest 相乗り）
既存 `fc_ingest` 夜間バッチの `uregi` 分岐から、対象 70 店舗を**アカウント単位で直列**に処理する。新規スケジューラは作らない。`_execute_run` は「対象店舗の列挙 → 各店舗で `fetch_daily_sales` 呼び出し → `fc_sales` upsert」の既存フローを維持し、`fetch_daily_sales` の内部だけ RPA 化する。

### (6) 認証情報の暗号化保管（既存機構再利用）
Uレジ資格情報は既存 `fc_credentials.py` ＋ `env_settings_store.py` の暗号化機構で保管・復号する。新しい暗号化機構は作らない。復号値はメモリ上のみで扱い、ログ・例外メッセージに出さない。

### (7) 冪等性・重複排除
`fc_sales` の既存 upsert キー（店舗 × 日付 × 明細キー）で冪等化する。まとめ取りで同一日が複数回取得されても重複行を作らない。RPA 途中失敗で部分取得になっても、再実行で欠損日が補完される設計とする。

### (8) エラーハンドリングとアカウントロック対策（最重要）
- **並列数上限**: `UREGI_RPA_MAX_CONCURRENCY` で上限。既定は保守的（アカウント共有の可能性を考慮し、同一アカウントは必ず直列＝実質 1）。
- **ログイン失敗時はリトライしない**（固定方針。`UREGI_RPA_RETRY_ON_LOGIN_FAILURE` は存在しても既定 false を維持すべき旨を明記）。
- **1 店舗 1 回ログイン＋月範囲まとめ取り**でログイン回数を削減。
- **ロック検知**: ログイン失敗画面の文言／回数超過メッセージを検出したら、その店舗を `login_failed` で確定し、以降その run ではそのアカウントに再接続しない。
- DOM 変更・タイムアウト・ダウンロード失敗は店舗単位で `failed` 確定し、他店舗の処理は継続する（1 店舗の失敗で全体を止めない）。

### (9) ブラウザバイナリのコンテナ同梱
smart-order の `Dockerfile` に Playwright Chromium を同梱する必要がある。可否・方式は §5 で論じる（本タスクでは Dockerfile を変更しない）。

### (10) 監視・ログ・取込状況可視化
取込ジョブの状態（queued/running/succeeded/failed/login_failed）と件数・所要時間を状態テーブルに記録し、「取込状況」画面で店舗別に可視化する。認証情報はログに出さない。

### (11) 手動実行経路の設計 ★本イシューで明示 carryover された要件
- 既存 `/api/fc/ingest/run-now`（`run_now_for_schema`）に **`store_id` 単位の指定**を通す。schema 全体ではなく単一店舗を指定できるようにする。
- **`budget_seconds=30` は HTTP API 前提値**。RPA は 1 店舗で数十秒〜数分かかるため**同期実行では必ずタイムアウトする**。
- 対処: **非同期キュー投入＋ポーリング表示**。run-now は同期で取込を走らせず、**ジョブを登録して `job_id` を即時返却**する。「今すぐ取込」画面は `job_id` を使って状況ポーリング API を叩き、進捗（queued→running→succeeded/failed）を表示する。
- 画面表示追加は **新クラス名のみ**（§31、既存 CSS 変更禁止）。

---

## 2. 新規作成・変更予定ファイル一覧（実装フェーズ用・本タスクでは作成しない）

| ファイル | 区分 | 予定内容 |
|---|---|---|
| `vgt-smart-order-system/app/main_system/fc_uregi.py` | 変更 | `verify_auth`/`fetch_daily_sales` の内部を RPA 化（シグネチャ維持）。Playwright 操作・CSV パースを内包 |
| `vgt-smart-order-system/app/main_system/fc_ingest.py` | 変更（最小） | `_execute_run` の `uregi` 分岐から店舗単位呼び出し。run-now の非同期ジョブ投入経路を追加 |
| `vgt-smart-order-system/app/main_system/fc_models.py` | 変更 | 取込ジョブ状態テーブルの ORM 追加（§3） |
| `vgt-smart-order-system/app/main_system/views_fc.py` | 変更 | run-now に `store_id` パラメータ追加、状況ポーリング API 追加、画面への状況表示（新クラス名） |
| `vgt-smart-order-system/app/main_system/fc_uregi_rpa.py`（候補） | 新規（任意） | RPA セレクタ定義とブラウザ操作を `fc_uregi.py` から分離する場合の受け皿 |
| マイグレーション（新規） | 新規 | 取込ジョブ状態テーブル DDL（§3） |
| smart-order `Dockerfile` | 変更（§5 で可否判断） | Playwright Chromium 同梱 |

> 上記はすべて姉妹レポ所管。本 giip-3710 タスクでは**一切作成・変更しない**。

---

## 3. テーブル定義案（既存再利用と追加を区別）

### 3-1. 再利用（新規作成しない）
- **売上明細**: 既存 `fc_sales` 系テーブル。RPA で取得した行も既存 upsert キーでそのまま格納する。必要なら provenance 用に `source` 相当列（既存にあれば再利用）へ `uregi` を記録。
- **認証情報**: 既存 `fc_credentials` ＋ `env_settings_shared_value`（暗号化）。Uレジ資格情報を同機構で保管。

### 3-2. 追加案（取込ジョブ状態テーブル）
run-now の非同期化（要件 11）と取込状況可視化（要件 10）のために、取込ジョブの状態テーブルを 1 本追加する。既存に相当するバッチ実行履歴テーブルがある場合は**追加列で拡張**し、無ければ新規作成する（実装フェーズで既存スキーマを確認し判断）。

| 列名（案） | 型（案） | 用途 |
|---|---|---|
| `job_id` | UUID / BIGINT PK | ジョブ識別子（run-now が即時返却） |
| `schema` | VARCHAR | 対象テナント schema |
| `store_id` | VARCHAR / INT | 対象店舗（手動実行の粒度） |
| `source` | VARCHAR | 取込元。本件は `uregi` |
| `trigger` | VARCHAR | `scheduled` / `manual` |
| `status` | VARCHAR | `queued` / `running` / `succeeded` / `failed` / `login_failed` |
| `requested_by` | VARCHAR | 手動実行者（任意） |
| `queued_at` / `started_at` / `finished_at` | TIMESTAMP | 投入・開始・終了時刻 |
| `target_date_from` / `target_date_to` | DATE | まとめ取り期間 |
| `rows_ingested` | INT | 取込件数 |
| `error_code` | VARCHAR | 失敗分類（`login_failed`/`dom_changed`/`timeout`/`download_failed` 等。**認証情報は含めない**） |
| `error_detail` | TEXT | 失敗詳細（マスキング済み） |

> インデックス案: `(schema, store_id, status)`, `(status, queued_at)`（キュー取り出し用）。

---

## 4. 人間側で設定が必要な環境変数名一覧（値は書かない・用途のみ）

**全て §0-c に従い DB（`env_settings_shared_value`）管理＋`env_settings_runtime` 経由読み取り**（ARM 直書き禁止。例外 5 変数のみ ARM 可）。

| 変数名（案） | 用途 |
|---|---|
| `UREGI_LOGIN_URL` | Uレジ ログイン画面 URL |
| `UREGI_SALES_EXPORT_PATH` | 売上実績 CSV エクスポート画面への遷移パス／ルート |
| `UREGI_RPA_MAX_CONCURRENCY` | 同時ブラウザセッション上限（アカウントロック防止の最重要ノブ。同一アカウントは実質 1） |
| `UREGI_RPA_INTER_STORE_DELAY_MS` | 店舗間の待機（ジッタ付き。ロック回避） |
| `UREGI_RPA_NAV_TIMEOUT_MS` | ページ遷移・操作タイムアウト |
| `UREGI_RPA_SESSION_TIMEOUT_MS` | 1 店舗あたりセッション全体の時間予算 |
| `UREGI_RPA_DOWNLOAD_DIR` | CSV 一時ダウンロード先ディレクトリ |
| `UREGI_RPA_HEADLESS` | ヘッドレス可否（デバッグ時のみ false） |
| `PLAYWRIGHT_BROWSERS_PATH` | コンテナ内ブラウザバイナリ配置パス |
| `UREGI_RPA_RETRY_ON_LOGIN_FAILURE` | ログイン失敗時リトライ可否。**既定 false を維持すべき旨を運用に明記**（存在しても true にしない） |

> いずれも**値は本書に書かない**。実在の URL・資格情報・テナント固有値はプレースホルダ扱い。

---

## 5. 設計上のリスクと懸念箇所

### 5-1. Uレジ側 DOM 変更耐性（高）
Uレジ管理画面の UI 変更でセレクタが壊れると全店舗が一斉失敗する。対策: セレクタを一箇所（RPA セレクタ定義）に集約し、ラベル／role ベースの堅牢なセレクタを優先。壊れたら早期失敗＋`dom_changed` で確定し、取込状況画面で可視化してアラート。

### 5-2. アカウントロック（最重要）
ログイン失敗の繰り返しや過剰な並列ログインでアカウントがロックされると、以降の全取得が不能になる。**最も強く明記する方針**:
- **ログイン失敗時はリトライしない**（固定）。
- **並列数上限**（`UREGI_RPA_MAX_CONCURRENCY`）。同一アカウントは必ず直列。
- **1 店舗 1 回ログイン＋月範囲まとめ取り**でログイン回数を根本削減。
- 店舗間に待機＋ジッタ。ロック検知時はそのアカウントをその run で以降スキップ。

### 5-3. ブラウザバイナリのコンテナ同梱（中）
smart-order コンテナに Playwright Chromium を同梱する必要がある。
- **可否**: 可能。方式は (a) `mcr.microsoft.com/playwright` 系ベースイメージの採用、または (b) 既存ベースイメージに `playwright install --with-deps chromium` をビルド時実行。
- **懸念**: イメージサイズ増（数百 MB）、ビルド時間増、コールドスタート。既存 `scripts/package.json` に Playwright 資産があるなら版を揃える。
- 本タスクでは Dockerfile を変更しない（可否論述のみ）。

### 5-4. 70 店舗の所要時間（中）
1 店舗数十秒〜数分 × 直列（アカウント単位）で夜間バッチ枠に収まるかを要見積り。アカウント共有状況により総所要が大きく変わる。夜間ウィンドウ超過時はアカウント並列度の範囲内で安全に分散。

### 5-5. `fc_uregi.py` 既存 API 前提との整合（中）
既存は HTTP API 前提。**シグネチャ `verify_auth`/`fetch_daily_sales` を維持し内部のみ RPA 化**することで、`fc_ingest._execute_run` 側の変更を最小化する。戻り値の形（売上明細の行表現）を既存 upsert が期待する形に合わせる。

### 5-6. run-now 同期タイムアウト（要件 11）
`budget_seconds=30` 同期実行では RPA は必ずタイムアウトする。**非同期キュー投入＋ポーリング**で回避（§1-(11)、§3-2）。この非同期化を怠ると手動実行が常に失敗する。

---

## 6. 検証計画（記載のみ・本タスクでは実行しない）

> **前提**: demo テナント `vtsmodemovegetrade` のみを使用する。**`vtsmomaruei` は読み取り専用・一切触らない**。実在の認証情報は使わずプレースホルダ／demo 専用資格情報で行う。

実装フェーズでの手動検証手順（設計）:
1. demo テナント `vtsmodemovegetrade` の 1 店舗について、Uレジ demo 資格情報を `fc_credentials`（暗号化）へ登録（プレースホルダ運用）。
2. コンテナに Playwright Chromium が同梱されていることを確認（`PLAYWRIGHT_BROWSERS_PATH` 配下の存在チェック）。
3. 「今すぐ取込」画面から対象 `store_id` を指定して run-now を実行 → **即時に `job_id` が返ることを確認**（同期タイムアウトしないこと）。
4. 「取込状況」画面で `job_id` の状態が `queued`→`running`→`succeeded` に遷移することをポーリング表示で確認。
5. `fc_sales`（demo schema）に当該店舗・対象期間の売上行が冪等に格納されていることを確認。再実行して重複行が増えないこと（冪等性）を確認。
6. 異常系: わざと誤った資格情報で 1 回実行し、`login_failed` で確定し**リトライしない**こと、他店舗処理が巻き込まれないことを確認。
7. UTF-16LE/TAB の CSV が正しくデコード・パースされ、BOM 有無・改行コード差で壊れないことを確認。

検証は demo テナントに閉じ、ログ・画面に認証情報が出ないことを併せて確認する。

---

## 7. 完了判定

本タスクは**設計のみ**であり、人間による設計レビューが必要なため、実処理完了後の状態は **REVIEW**。設計書（本ファイル）とタスクファイルの GitHub URL を報告コメントに併記する。
