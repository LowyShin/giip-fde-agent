# secwatch: Azure ログを az 経由で generic 取込・監視対象化 — 作業指示書(spec)

- **taskId**: giip-3869 （関連: secwatch 本体 giip #3833）
- **role**: `.agent/roles/infra-architect.md`（インフラ+収集器実装）
- **status**: 承認待ち（prod 設定変更は未実行）
- **対象repo**: `giip-fde-agent`（secwatch 本体 `scripts/secwatch/`、運用 `docs/60-operations/secwatch-agent.md`）

## 0. 目的
secwatch は正規化イベント(JSON-lines, §5 スキーマ)を source として取込み、1次前段フィルタ後に Jev ゲートウェイへ送る。
現状 source は AWS 前提(aurora_audit/waf/cloudfront)。本タスクは **Azure のログを `az` で抽出し、`generic` source として
secwatch に供給**する収集器を追加する。ユーザー選択 = A+B+C。

## 1. 現状調査（2026-10-18 実測・az)
| 項目 | 結果 | 含意 |
|---|---|---|
| prod PG `pg-vgt-restore-20260601` 診断設定 | **無し(`[]`)** | PostgreSQL ログが Log Analytics に流れていない |
| pgaudit | `shared_preload_libraries=pg_cron,pg_stat_statements`（pgaudit 無） | 監査ログ未生成 |
| `log_statement` | `none` | SQL 文ログ未生成 |
| Log Analytics WS | `rg-vegetrade-prod` に存在 | 診断設定の送信先に使える |
| Front Door / App Gateway | **0 件** | **C(WAF) は対象リソース無し → 今回 N/A**（WAF 導入は別タスク） |

→ **「抽出」以前にログが生成・収集されていない**。本タスクは「有効化 → LA ルーティング → 抽出 → generic 取込」の順になる。

## 2. スコープ
- **A. PostgreSQL SQLi 監視**（secwatch 本来目的）: 前提=監査/文ログ有効化 + 診断設定→LA。**prod 設定変更 + PG 再起動（`shared_preload_libraries` 変更時）が必要 → 要承認**。
- **B. App Service HTTP 監視**: `az webapp log`（または診断設定→LA）で HTTP アクセスログ。**DB 再起動不要**。
- **C. WAF/Front Door**: 対象リソース無しで **N/A**（将来 WAF 導入時に追加）。

## 3. 設計（az 収集器 → generic source）
新規 `scripts/secwatch/azure/` に収集器を置く(secwatch 本体は非改変):
```
Azure ログ源 → (az 抽出) → 正規化 JSON-lines(§5) → secevt_collect.py --source generic
            → secevt_agent.py(マスキング/前段/送信) → Jev ゲートウェイ
```
- **A 抽出**: `az monitor log-analytics query -w <WS> --analytics-query "AzureDiagnostics | where Category=='PostgreSQLLogs' ..."`（診断設定で PostgreSQLLogs を LA へ出す前提）。各行 → `{src:'generic', ts, db, dbuser, op:'QUERY', sql_shape:<文>, retcode, origin:{source:'azure_pg_audit', system:'pg-prod', location:<WS/table>, ref:<queryId/行>}}`。
- **B 抽出**: `az webapp log download`（zip→HTTPログ）or 診断設定(AppServiceHTTPLogs→LA)を KQL。各行 → `{src:'generic', ts, req_uri, req_args_shape:<query>, retcode:<status>, client_ip_class, ua_class, origin:{source:'azure_appsvc_http', system:<app>, ...}}`。
- **source 登録**: `secwatch.sources.json` に `generic` source を追加（file=収集器が書く JSON-lines、since_offset で増分）。
- **スケジュール**: §6 の cron（Linux）で `secevt_run.py` を定期起動。収集器は run の前段 or source の前処理として走らせる。
- **イベント欄マッピング**（§5 準拠。sql_shape/req_args_shape はエージェントが**マスキング後**に前段フィルタ§10 を適用。req_uri は非マスキング）。

## 4. 前提作業（prod 設定変更・要承認・§0-c/§0-a 準拠）
1. **A-1 ログ有効化**（どちらか）:
   - 低影響: `log_statement='ddl'` or `'mod'`（再起動不要の動的パラメータ。全文は `'all'` だが量大）。**pgaudit は `shared_preload_libraries` 変更=PG 再起動**必要。
   - 推奨: まず `log_statement`（再起動不要）で PoC → 必要なら pgaudit。
2. **A-2 診断設定**: PG サーバ → `PostgreSQLLogs` を `rg-vegetrade-prod` の LA WS へ送る診断設定を追加。
3. **B-1**: App Service の HTTP ログ（`az webapp log config --web-server-logging filesystem` もしくは診断設定→LA）。
4. これら prod 変更は **dry-run/提示→ユーザー承認後に実行**（本セッションの教訓 CLAIM-5520）。

## 5. dev PoC 先行（推奨・prod 非影響）
- `pg-vegetrade-dev` + dev App Service で A/B 収集器を先に作り、合成/実ログで `secevt_run.py --dry-run` まで検証（候補数・payload 分類 §3）。
- 検証OK後に prod へ設定変更+展開。

## 6. 完了条件
- [ ] A: PG ログ→LA→az抽出→generic 正規化→`secevt_agent.py --dry-run` で `secevt_batch_audit` に分類
- [ ] B: App Service HTTP→az抽出→generic→`secevt_batch_waf/cf` 相当に分類
- [ ] `secwatch.sources.json` に Azure source 登録 + cron 登録
- [ ] 攻撃サンプル(`secevt_sample.py --only attack`)が候補判定されることをルーティングで確認
- [ ] prod 設定変更は承認済み・最小権限・§0-c 準拠

## 7. 参照 / K-Layer
- 参照: `docs/60-operations/secwatch-agent.md`(§1-12), `scripts/secwatch/README.md`, SPEC_JEV_SQLI_DETECTION.md, giip #3833
- 作業後: k-layer に「Azure→secwatch generic 収集」パターンと prod ログ有効化の可否/影響を claim 化
