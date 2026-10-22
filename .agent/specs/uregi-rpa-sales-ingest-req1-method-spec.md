<!--
taskId: giip-3707
title: [1/4] Uレジ売上データ自動取得（RPA方式）の設計
csn: 70418
status: DESIGN-ONLY（実装・アプリコード変更は本タスク範囲外）
related:
  - giip-3710（[4/4] 概観設計 .agent/specs/uregi-rpa-sales-ingest-spec.md）
  - giip-3709（[3/4] 要件(7)-(10)詳細 .agent/specs/uregi-rpa-sales-ingest-detail-spec.md）
  - giip-3708（[2/4] 要件(2)-(6)詳細 .agent/specs/uregi-rpa-sales-ingest-req2-6-spec.md）
-->

# Uレジ売上データ自動取得（RPA方式）— 既存資産棚卸し＋Playwright 実行方式選定 設計書（[1/4] 基盤）

- **taskId**: `giip-3707`
- **GIIP issue**: isn=3707 `[1/4] Uレジ売上データ自動取得（RPA方式）の設計`
- **CSN**: 70418
- **位置づけ**: FC連携サブイシューチェーンの **1/4（基盤・方式選定フェーズ）**。本書は要件 **(1) 既存資産の棚卸しと再利用方針の確定** と、チェーン全体の前提となる **Playwright 実行方式の 2 案比較 → 推奨 1 案の確定** を担う。概観（要件 (1)〜(11) の全体像）は姉妹 giip-3710 の `.agent/specs/uregi-rpa-sales-ingest-spec.md` を正とし、要件(2)〜(6)は giip-3708、要件(7)〜(10)は giip-3709 を参照する。
- **成果物スコープ**: 設計のみ。アプリケーションコードの実装・変更・コミットは行わない。commit/push 対象は本書・`.agent/tasks/giip-3707.md`・`.agent/knowledge/notes/uregi-rpa-ingest-req1-method.md` のみ。
- **作業ブランチ**: 本レポ（giip-fde-agent）では feature ブランチ → PR。設計書が言及する vgt-smart-order-system 側の実装は dev-first（作業ブランチ dev、stg/main への PR は作らない）を前提に記述する。

---

> **成果物パスの差異について（[SCOPE-RECONCILED]）**: イシュー本文は本タスクの「唯一の成果物」を `.agent/specs/uregi-rpa-sales-ingest-spec.md` と指定しているが、同パスは姉妹 giip-3710（[4/4] 概観）が既にコミット済（commit `9f3285f`, PR #143, taskId=giip-3710）であり、さらに姉妹 giip-3709（PR #144）・giip-3708（PR #145）も同パス衝突を回避してそれぞれ別ファイルへ分離済み。同一ファイルを本 3707 で上書きすると 3710 の taskId/所管を破壊し cross-issue 汚染（giip #2459 / rule `50_bot_pr_scope_discipline`）となる。チェーンは「ひとつの機能のひとつの仕様」を 4 イシューで協調構築する構造であるため、本 3707（[1/4] 基盤・方式選定）は別パス `uregi-rpa-sales-ingest-req1-method-spec.md` に分離し、概観(3710)・詳細(3708/3709)を相互参照する形とした。実装フェーズでは 4 書を併読する。

---

## 0. 本書が従う絶対制約（giip-3710 §0-1 を継承）

- **実在の認証情報を一切含めない**。企業コード／担当者コード／パスワードは本書・コード・ログ・コミットのいずれでもプレースホルダ表記のみ。
- **`vtsmomaruei` は読み取り専用・絶対に触らない**。検証前提は demo テナント `vtsmodemovegetrade` のみ。
- **環境変数・App Settings・Azure リソースの変更は本タスクでは行わない**。必要な変数は「名前と用途」のみ列挙する（§0-c: 追加設定値は ARM 直書きでなく DB `env_settings_shared_value` 管理＋`env_settings_runtime` 経由読み取り。例外は `DB_HOST`/`DB_NAME`/`DB_USER`/`DB_PASSWORD`/`ENV_SETTINGS_DB_ENC_KEY` の 5 つのみ）。
- **CSS 不変原則（§31）**: 画面への表示追加を設計する場合も既存 CSS の変更は禁止。新クラス名での追加のみ。
- **既存シグネチャ維持**: `verify_auth` / `fetch_daily_sales` のシグネチャを維持し、内部実装だけ RPA に差し替える。`fc_ingest._execute_run` の `uregi` 分岐変更を最小化する。
- **本レポ（giip-fde-agent, csn 70418 運用）には下表のファイルは存在しない**。姉妹 `vgt-smart-order-system` / `vgt-vegetrade-auth-api` レポ所管であり、本設計はイシュー本文に記載されたインターフェース名を前提に記述する。実装フェーズで実ファイルのシグネチャと差異があれば、シグネチャ維持の原則に従って実ファイル側を正とする。

---

## 1. 要件(1) — 既存資産の棚卸しと再利用方針の確定

> **設計原則**: 「新規独自実装を起こさない」。RPA 化で**新たに起こすのはブラウザ操作と CSV パースの内部だけ**であり、認証情報の保管・復号、売上の upsert、取込のディスパッチ、設定値の読み取り、画面導線は**すべて既存資産を再利用**する。以下はその棚卸しと、各資産の再利用判断である。

### 1-1. 再利用資産の棚卸し（姉妹レポ所管・本タスクでは変更しない）

| 既存資産 | 所管 | 役割 | 本 RPA 設計での再利用判断 | 新規実装の要否 |
|---|---|---|---|---|
| `fc_uregi.py`（`verify_auth` / `fetch_daily_sales`） | vgt-smart-order-system | API 前提プレースホルダ | **シグネチャ維持・内部のみ RPA 差替**。呼び出し側（`fc_ingest`）から見た契約は不変 | 内部実装のみ新規（ブラウザ操作・CSV パース） |
| `fc_ingest.py`（`_execute_run` の `uregi` 分岐） | vgt-smart-order-system | 取込ディスパッチャ | **分岐の呼び出し規約を維持**。非同期ジョブ投入経路の追加は最小変更（要件11） | 追加は最小（非同期投入のみ） |
| `fc_credentials.py` ＋ `env_settings_store.py`（Fernet 暗号化） | vgt-smart-order-system / vgt-vegetrade-auth-api | FC 認証情報の暗号化保管・復号 | **そのまま再利用**。Uレジ資格情報（企業/担当者/パスワード）を同一機構で保管。新しい暗号化機構は作らない | 不要（姉妹 giip-3702/3703 で FC uregi 暗号化保管の再利用を実証済み） |
| `fc_sales.py`（売上明細 upsert） | vgt-smart-order-system | 売上日次の冪等 upsert | **既存 upsert キーを再利用**（`store_id × business_date × source`）。RPA 取得行も同経路で格納 | 不要 |
| `fc_models.py` | vgt-smart-order-system | 取込関連 ORM | 取込ジョブ状態テーブルの追加のみ（要件10/11、3710 §3-2） | 追加 1 テーブルのみ |
| `views_fc.py`（`run_now_for_schema`） | vgt-smart-order-system | 画面・API | run-now の `store_id` 対応・状況ポーリング API 追加（新クラス名のみ、§31） | 最小追加 |
| `env_settings_runtime.py` | vgt-smart-order-system | 設定値の DB 読み取り | **そのまま再利用**。新規環境変数の読み取り元（ARM 直書きしない、§0-c） | 不要 |
| `tools/demo-autopilot/src/lib/session.ts` | vgt-smart-order-system（Node/TS） | Playwright 既存資産（セッション管理） | **方式選定の参考・流用検討対象**（§2 で論じる）。Node 版 Playwright が既にビルド/CI に乗っている実績の根拠 | 方式次第 |
| `scripts/package.json`（Playwright 依存宣言） | vgt-smart-order-system | Node Playwright 版宣言 | ブラウザ同梱・版合わせの参考（§3） | 不要 |
| smart-order `Dockerfile` | vgt-smart-order-system | コンテナビルド | ブラウザバイナリ同梱の可否を**論じるのみ**（§3、本タスクで変更しない） | 実装フェーズで変更 |

### 1-2. 再利用方針の結論

1. **認証・暗号化・upsert・設定読み取りは一切新規実装しない**。これらは FC 連携基盤として既に動いており（giip-3702/3703 で Uレジ向け暗号化保管の再利用が live dev で検証済み）、RPA 化はこの基盤の「取得手段」だけを HTTP API → ブラウザ操作に差し替える。
2. **新規に起こすのは `fetch_daily_sales` 内部の RPA ロジック（ブラウザ操作＋CSV パース）と、要件10/11 のための取込ジョブ状態テーブル 1 本のみ**。それ以外の新規ファイルは任意（セレクタ分離用 `fc_uregi_rpa.py` / `fc_uregi_locators.py`、3709 CLAIM-URG-107）。
3. **既存の HTTP API 前提（`fc_uregi.py`）を覆すが、呼び出し契約は壊さない**。`fc_ingest._execute_run` 側の変更を最小化するため、`verify_auth` / `fetch_daily_sales` のシグネチャと戻り値の形（既存 upsert が期待する売上明細行表現）を維持する。

---

## 2. Playwright 実行方式の決定 — 2 案比較 → 推奨 1 案

> **判断基準（イシュー本文明示）**: 「Django App Service コンテナにブラウザバイナリを同梱できるか（イメージサイズ・`playwright install --with-deps` の是非）」を軸に、**Azure リソース変更を行わない前提で Dockerfile 変更のみで成立するか**を最優先で評価する。

### 2-1. 案 A — Python `playwright-python` を Django 管理コマンド内に閉じ込める

`fc_uregi.py`（Python）から `playwright-python`（sync/async API）を直接呼び、ブラウザ操作・ダウンロード・CSV パースまで同一プロセス内で完結させる。`fetch_daily_sales` の内部が純 Python のまま RPA 化される。

| 観点 | 評価 |
|---|---|
| 言語整合 | ◎ 取込パイプライン（Django/Python）と同一言語。戻り値を既存 upsert へ渡すのに IPC 不要 |
| 依存追加 | `playwright`(pip) を smart-order の Python 依存に追加。Chromium バイナリは `playwright install chromium`（＋ランタイム共有ライブラリは `--with-deps`） |
| Dockerfile のみで成立するか | ○ 可。既存 Python ベースイメージに `pip install playwright` ＋ `playwright install --with-deps chromium` をビルド時実行で成立。**Azure リソース変更不要** |
| 障害分離 | △ 同一プロセスゆえブラウザクラッシュ/ハングが Django ワーカーに影響しうる → 要件11 の**非同期ジョブ（別プロセス/別ワーカー）化**で緩和（3710 §1-(11)） |
| 既存資産の流用 | セレクタ知見は Node 版（`session.ts`）から移植が必要だが、ロジックは単純な画面操作であり移植コストは限定的 |
| 保守性 | ◎ 取込コードが 1 言語・1 リポに閉じる。デバッグ・ログ・例外ハンドリングが Django 側の既存機構に乗る |

### 2-2. 案 B — 既存 Node 版 Playwright を subprocess 起動し CSV パスを返す

`fc_uregi.py`（Python）から Node の Playwright スクリプト（`scripts/` 既存資産・`session.ts` 流用）を `subprocess` で起動し、ダウンロード済み CSV のパスを stdout/一時ファイル経由で受け取り、パース・upsert は Python 側で行う。

| 観点 | 評価 |
|---|---|
| 言語整合 | △ Python↔Node の 2 言語橋渡し。CSV パス・エラーコード・進捗を IPC（stdout/JSON/終了コード）で受け渡す契約が必要 |
| 依存追加 | Node ランタイム＋`@playwright/test`（既に `scripts/package.json` にある）＋Chromium。**Python コンテナに Node ランタイムを追加同梱**する必要 |
| Dockerfile のみで成立するか | △ 成立するが重い。Python ベースイメージに Node ランタイム＋npm 依存＋Chromium を載せる multi-stage が必要。イメージサイズ・ビルド時間が案 A より増 |
| 障害分離 | ◎ ブラウザは別プロセス。クラッシュしても Django ワーカーは無傷。タイムアウトは subprocess kill で確実に回収 |
| 既存資産の流用 | ◎ `session.ts` 等の Node Playwright 資産をほぼそのまま流用できる |
| 保守性 | △ 2 言語・2 依存ツリー・IPC 契約の保守。セレクタ変更時に Node 側を触る必要があり、取込ロジックが 2 リポ/2 言語に跨る |

### 2-3. 推奨 — **案 A（Python `playwright-python` を Django 管理コマンド内に閉じ込める）**

**根拠**:

1. **判断基準（Dockerfile のみで成立するか）で案 A が優位**。案 A は既存 Python イメージへ `pip install playwright` ＋ `playwright install --with-deps chromium` を足すだけで成立し、**Azure リソース変更も Node ランタイム追加同梱も不要**。案 B は Python コンテナへ Node ランタイムを別途同梱する multi-stage が必要でイメージ肥大・ビルド時間増を招く。
2. **保守性（要件9）で案 A が優位**。取込コードが Django/Python 1 言語・1 リポに閉じ、既存のログ・例外・設定読み取り（`env_settings_runtime`）機構にそのまま乗る。案 B の IPC 契約（CSV パス受け渡し・エラーコード橋渡し・進捗通知）は恒常的な保守負債になる。
3. **既存シグネチャ維持の原則に最も素直**。`fetch_daily_sales` が純 Python のまま内部を RPA 化でき、`fc_ingest._execute_run` 側の変更が最小で済む（§1-2、要件E）。
4. **案 B の唯一の明確な優位（プロセス障害分離）は、案 A でも要件11 の非同期ジョブ化で代替できる**。取込を Django ワーカー本体でなく**非同期ジョブ（別プロセス/別ワーカー）**として走らせれば、ブラウザのクラッシュ/ハングが同期 HTTP 経路や他ジョブを巻き込まない。すなわち案 A＋非同期化で案 B の分離利点を取り込める（3710 §1-(11)・§3-2、CLAIM-URG-213）。
5. Node 版 Playwright 資産（`session.ts`）は**セレクタ・ログイン手順の設計参考**として活用し、実装は Python へ移植する（ロジック自体は単純な画面操作であり移植コストは限定的）。

> **ただし条件つき**: Python ベースイメージへの Chromium 同梱が運用上許容できないサイズ/ビルド時間になる、または共有ライブラリ（`--with-deps`）の解決がベースイメージで困難と実装フェーズで判明した場合に限り、案 B（または `mcr.microsoft.com/playwright/python` ベースイメージ採用）へのフォールバックを検討する。この判断は §3 の Dockerfile 検証結果に従う。

---

## 3. Dockerfile 変更のみで成立するか（ブラウザバイナリ同梱の可否）

> **本タスクでは Dockerfile を変更しない。可否を論じるのみ**（3710 §5-3 を本書の方式選定に接続して具体化）。

- **可否**: **可能**。案 A（推奨）の場合、既存 Python ベースイメージに対し Dockerfile へ以下を追加するだけで成立し、**Azure リソース変更は不要**:
  - `pip install playwright`（smart-order の Python 依存に追加）
  - ビルド時に `playwright install --with-deps chromium`（Chromium バイナリ＋ランタイム共有ライブラリを同梱）
  - `PLAYWRIGHT_BROWSERS_PATH` でバイナリ配置パスを固定（3710 §4 の環境変数一覧に既出）
- **`--with-deps` の是非**: Chromium は追加 OS 共有ライブラリ（fonts/nss/atk 等）を要求する。`--with-deps` は Debian/Ubuntu 系ベースイメージで apt により一括解決するため**採用推奨**。ベースイメージが slim/Alpine 等で apt が無い／musl 系の場合は、代替として **`mcr.microsoft.com/playwright/python` 公式イメージをベース採用**（multi-stage）する方が確実。どちらも Dockerfile 変更のみで成立し Azure リソース変更は不要。
- **懸念**: イメージサイズ増（Chromium＋依存で数百 MB）、ビルド時間増、コールドスタート遅延。`scripts/package.json` に既存の Node Playwright 版があるなら**Chromium の版を揃える**（セレクタ挙動差の回避）。
- **結論**: 判断基準「Dockerfile 変更のみで成立するか」に対し **成立する（案 A）**。これが §2-3 で案 A を推奨する最大の根拠。

---

## 4. run-now 非同期化の必要性（要件11 への基盤的リスク明記）

- **`run-now` の `budget_seconds=30` は HTTP API 前提値**。RPA は 1 店舗で数十秒〜数分かかるため（3708 CLAIM-URG-211: 1 店舗 40〜120 秒以上）、**同期実行では必ずタイムアウトする**。
- これは案 A/案 B のいずれを採っても変わらない**方式非依存の構造的制約**であり、本 [1/4] 基盤設計で最も強く明記すべきリスクの一つ（アカウントロックと並ぶ）。
- **対処（基盤方針）**: run-now は同期で取込を走らせず、**ジョブを登録して `job_id` を即時返却**し、画面は `job_id` でポーリング表示する（3710 §1-(11)・§3-2、3708 CLAIM-URG-213）。この非同期化は、§2-3 で案 A を採る場合に**案 B のプロセス障害分離利点を代替で獲得する手段**でもある（§2-3 根拠4）。
- 画面表示追加は**新クラス名のみ**（§31、既存 CSS 変更禁止）。

---

## 5. アカウントロック対策（本 [1/4] 基盤での最強明記）

> イシュー本文「アカウントロックが最大のリスク」を基盤設計の必須前提として明記する。詳細な数値・並列設計は 3708（要件6）に委譲し、本書は方式選定が従うべき固定方針を宣言する。

- **ログイン失敗時はリトライしない**（固定方針。`UREGI_RPA_RETRY_ON_LOGIN_FAILURE` は存在しても既定 false を維持すべき）。
- **1 店舗 1 回ログイン＋月範囲まとめ取り**でログイン回数を根本削減（要件3/4、3708 CLAIM-URG-204）。この方針は §2 の実行方式選定より上位の制約であり、案 A/B どちらでも同一に適用する。
- **並列は別アカウント間のみ**。同一アカウント（企業コード）は必ず直列＝実質 1（3708 CLAIM-URG-210）。並列ログインがロック誘発の最大要因。
- ロック検知時はそのアカウントをその run で以降スキップし、1 店舗の失敗が他店舗を止めない（3710 §5-2）。

---

## 6. 検証計画（記載のみ・本タスクでは実行しない）

> **前提**: demo テナント `vtsmodemovegetrade` のみ。**`vtsmomaruei` は読み取り専用・一切触らない**。実在の認証情報は使わずプレースホルダ／demo 専用資格情報で行う。

本 [1/4]（方式選定）の実装フェーズ検証は、§2-3 の推奨（案 A）が成立することの確認に絞る:

1. **Dockerfile 成立確認**: 案 A の Dockerfile 追記（`pip install playwright` ＋ `playwright install --with-deps chromium`）でイメージがビルドでき、`PLAYWRIGHT_BROWSERS_PATH` 配下に Chromium バイナリが存在することを確認（Azure リソース変更なし）。
2. **最小 RPA 疎通**: demo テナント 1 店舗で `playwright-python` が Chromium を起動し、ログイン画面に到達できることを確認（実資格情報は使わずプレースホルダ／demo 専用）。
3. **既存シグネチャ維持確認**: `fetch_daily_sales` の内部を RPA 化しても呼び出し側 `fc_ingest._execute_run` の `uregi` 分岐が無改修（または最小改修）で動くことを確認。
4. **非同期経路確認**: run-now が同期実行せず `job_id` を即時返却すること（§4）。
5. ログ・画面・例外に認証情報が出ないことを併せて確認。

> 要件(2)〜(10) の個別検証は 3708/3709/3710 の検証計画に従う。本書は方式選定の成立確認のみを担う。

---

## 7. 完了判定

本タスクは**設計のみ**であり、人間による設計レビュー（要件(1) 再利用方針と Playwright 実行方式選定の承認）が必要なため、実処理完了後の状態は **REVIEW**。設計書（本ファイル）・タスクファイル・knowledge の GitHub URL を報告コメントに併記する。姉妹 giip-3710（概観）・giip-3709・giip-3708（詳細）と**併読**することを前提とする。

### 関連文書（4 書併読）

| イシュー | 役割 | ファイル |
|---|---|---|
| giip-3707（本書 [1/4]） | 基盤・既存資産棚卸し＋実行方式選定 | `.agent/specs/uregi-rpa-sales-ingest-req1-method-spec.md` |
| giip-3708（[2/4]） | 要件(2)-(6) 詳細 | `.agent/specs/uregi-rpa-sales-ingest-req2-6-spec.md` |
| giip-3709（[3/4]） | 要件(7)-(10) 詳細 | `.agent/specs/uregi-rpa-sales-ingest-detail-spec.md` |
| giip-3710（[4/4]） | 概観（要件 1-11 全体像） | `.agent/specs/uregi-rpa-sales-ingest-spec.md` |
