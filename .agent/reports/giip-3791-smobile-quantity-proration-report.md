# giip-3791 調査報告 — 【S-MOBILE/SO】数量修正時に加工指示明細が按分され端数化する原因調査 [3/3]

- isn: 3791（チェーン 3/3。1/3=isn=3789・2/3=isn=3790 と同一本文の人為分割。結論は 3 件で一致）
- CSN: 70418
- 種別: **調査・報告のみ**（コード変更・DB 変更・Migration 適用なし）
- 対象環境: DEV のみ（やまに青果 / 一般 / 2026-09-23）
- 調査対象リポジトリ（**参照のみ・変更なし**）: `LowyShin/vgt-smart-order-system`（`_tmp/vgt-smart-order-system`、dev HEAD `00de2aa2`）。SS は `LowyShin/vgt-smart-stock`。
- 成果物の出力／push 先は **giip-fde-agent 本リポ**（`.agent/reports/`・`.agent/tasks/`）。イシュー本文が例示する `https://github.com/LowyShin/smartorder-works/blob/dev/...` はテンプレ由来の齟齬であり、本報告書は giip-fde-agent の GitHub URL で併記する（[H] gicSn 28059 で確定した参照先訂正に従う）。
- 症状: S-MOBILE モバイル管理から数量を修正すると、加工指示書 `/packaging_printing/` の同一原体が複数行に分割され注文数量が端数化（298.87 / 0.57 / 0.56 ≒ 300）

> **進断連続性(giip #1195/#1210)**: 兄弟 [1/3]=3789（PR#153 MERGED）・[2/3]=3790（PR#152 MERGED）の確定済み報告を読了のうえ、本 [3/3] は主要コード事実を dev HEAD `00de2aa2` で**現物再確認**（丸写しせず）した結果を記載する。3 件の結論は一致する。

---

## 結論（要約）

**SO のコード上には「1 件の受注明細を複数の端数行に按分・分割する」ロジックは存在しない。**
数量修正 API（`mobile_order_modify`）は既存の `OrderLedger` 行を **その場で `bulk_update`** するだけで、
行の新規作成・削除・再作成・BOM 再展開を一切行わない。加工指示書 `/packaging_printing/`（ビュー
`get_mounting_data`）は `OrderLedger` 行を **集約せず素のまま** 返し、画面側 JS も
`(year, saving_id)` 1 件につき 1 表示行で、按分も分割も行わない。

したがって観測された「同一原体が 298.87 / 0.57 / 0.56 の 3 行」は、**表示側の按分（系統C）でも、数量修正処理による
分割・二重計上（系統B）でもなく**、その 3 行が **受注登録の時点で既に別々の `OrderLedger` レコード
（同一 material_id/standard_id・別 saving_id）として保存されていた** 可能性が最も高い。
確定には DEV DB の該当行 SELECT（`created_at`/`updated_at`/`staff_name`/`ticket_id` の確認）と、
実際の「S-MOBILE モバイル管理」画面での再現が必要で、これは本タスクの範囲外（人手・REVIEW）である。

---

## 1. 按分の発生箇所 —「表示側の分割」か「データ自体の分割」か

### 事実（dev HEAD `00de2aa2` で再確認）

- 加工指示書 `/packaging_printing/` のデータ取得は `get_mounting_data`（`app/main_system/views.py:13442-`）。
  `OrderLedger.objects.filter(shipping_date=...).values(...).order_by('client_id','end_destination_id','material_id','standard_id','saving_id')`
  で取得しており、**`annotate`/`aggregate`/`GROUP BY`/`Sum`/`Count` を一切行っていない**（13442-13510 を grep で確認＝0 件）。取得後の Python 加工も
  `operating_name`/`processing_name`/`work_name` ラベル付けのみで、**行の分割・合算・按分は無い**。
- 画面の差分監視 JS `app/static/js/screens/packaging-printing-panel.js:547-548` の `rowKey(row)` は
  `return row.year + '|' + row.saving_id;`。**1 `OrderLedger` レコード（= 1 saving_id）につき 1 表示行**。
  表示側で 1 行を複数行に割る処理は無い（603-795 のロジックはライブ差分ポーリング用で、分割とは無関係）。

### 判断

- **系統C（帳票側 group by キーの粒度差による表示上の分割）はほぼ否定される。** 画面は `OrderLedger` を
  素のまま 1 レコード 1 行で出すので、3 行見えているなら **DB に 3 レコード存在する**。
- よって「データ自体が 3 レコードに分割保存されている」。発生箇所は **受注登録（INSERT）経路** のいずれか。

---

## 2. 計算根拠 — 端数（298.87 / 0.57 / 0.56）の算出式

### 事実

- `OrderLedger.quantity` は `models.FloatField`（`app/main_system/models.py:467`、再確認済）。小数（端数）は正規に格納可能。
- 保存時の数量は顧客別の小数桁（既定 2 桁）に量子化される（兄弟 3790 で特定した `quantize_quantity_for_client`）。
  298.87 / 0.57 / 0.56 はいずれも 2 桁で、この量子化規則に矛盾しない。
- 298.87 + 0.57 + 0.56 = **300.00（ちょうど）**。3 行の合計が元数量に一致する。

### 判断（推測）

- 合計がちょうど 300.00 になる点は、**3 行がもともと 1 件 300 を「分けた」もの**であることを強く示唆する。
  ただし **SO の INSERT 経路にこの分割を行う式は見当たらない**（§3 参照）。したがって分割は
  **SO の受注保存ロジックの外**（取込元データ、または別システム／別画面）で起きた可能性が高い。
  端数そのものの算出式を SO コードから特定することはできなかった（**事実**: 分割式が存在しない）。

---

## 3. 仕様か不具合かの判断 — 修正経路と登録経路

### 事実（数量修正経路 — dev HEAD `00de2aa2` で再確認）

- `mobile_order_modify`（`app/main_system/mobile_order.py:1350-`）:
  - 対象 `OrderLedger` 行を取得し、各行の `quantity` を新値に差し替え、金額を再計算し、
    `OrderLedger.objects.bulk_update(order_ledgers, _update_fields)`（同 ~1428 行）**で既存行をその場更新するだけ**。
  - 関数本体（1350-1450）を grep したところ **`.create(` / `bulk_create` / `.delete(` は 0 件**。BOM 再展開（`enqueue_purchase_from_order_lines`）も呼ばない。
- → **数量修正それ自体は 1 行を 3 行に増やせない。** 系統B（修正時の削除再作成漏れ＝差分の二重計上）は
  **モバイル数量修正経路には存在しない**。

### 事実（受注登録＝行作成経路は 3 本のみ／兄弟 3790 特定・本 [3/3] 追認）

| 経路 | 箇所 | 行の作り方 |
|---|---|---|
| モバイル受注送信 | `mobile_order.py:1261,1319` | `items` の **1 要素 → 1 行**（`saving_id_base + idx`） |
| SMART-AI 読取取込 | `smart_ai_service.py:623,670` | グループ内の **1 行 → 1 行**（`saving_id_base + offset`） |
| 受注入力（単件） | `views.py:7371` | **1 明細 → 1 行** |

- いずれも **1 入力行 → 1 `OrderLedger` 行**。入数・注文容量で 1 明細を複数行に割るループは **どの経路にも無い**。
- SMART-AI 取込には再取込時の delete→再作成（`smart_ai_service.py:760`）が存在するが、これは取込（INSERT）経路であり
  モバイル数量修正経路ではない。

### 事実（BOM 按分は別テーブル・別トリガ — 再確認）

- 多段 BOM 展開 `bom_expand.expand()`（`app/main_system/bom_expand.py:172`、`loss_factor` 乗算は同 211 行）は
  歩留を浮動小数的に乗算して端数を生む（系統A の端数演算候補）。
  **ただし書き込み先は `BomPurchase`（仕入データ）であり `OrderLedger` ではない**
  （`bom_purchase.py:353` `BomPurchase.objects.bulk_create(rows)`）。
- BOM 展開のトリガは **受注 CREATE 経路のみ**。**`mobile_order_modify` は BOM 展開を呼ばない。**
- → 系統A（歩留・換算係数の浮動小数演算による端数）は **加工指示書 `/packaging_printing/`（＝`OrderLedger`）には流れ込まない**。

### 判断

- 「仕様か不具合か」は **SO コードだけでは断定不可**。SO 側に分割を生む式が無いため、
  3 行が「どの経路で・いつ」作られたかが鍵となり、それは DB の行メタデータ（§5-0 の SELECT）でしか分からない。
- 現時点の最有力仮説（**推測**）: 3 行は **受注登録の時点で既に 3 レコードとして入っていた**
  （取込元ドキュメント／モバイル送信ペイロードが同一原体を 3 明細として持っていた、
  もしくは本調査で未特定の「S-MOBILE モバイル管理」側の編集経路が分割した）。
  「数量修正で金額が再計算され表面化する」だけで、修正が分割の原因ではない。

---

## 4. 影響範囲 — 同一按分が走る他経路・データ伝播

### 事実

- `OrderLedger` を作る経路は §3 の 3 本のみ。いずれも 1:1。
- 数量を書き換える経路: `mobile_order_modify`（その場更新）、`update_operating_division` /
  `update_processing_division` / `update_work_check`（`views.py:13529-`、作業区分・チェックのみ。数量は触らない）。
- BOM 展開（`bom_purchase`/`bom_expand`）は `BomPurchase` にのみ書き、`OrderLedger` を分割しない。
- SS（`vgt-smart-stock`）在庫引当は加工指示書のデータ源（SO の `OrderLedger`）に関与しないと推定（**推測**・ツリー外未参照）。

### 事実（伝播）

- 加工指示書 `/packaging_printing/` は `OrderLedger` を直接読む。**3 レコードあれば加工指示書は 3 行**、
  ピッキング・請求・集計も同じ `OrderLedger` を源とするため、**3 レコード前提の数量がそのまま伝播**する。
- つまり「表示だけの問題」ではなく、**データ源が 3 レコードである以上、下流の全帳票・集計に波及する**。

---

## 5. 修正案（提案のみ・実装しない）

> まず **原因の確定（下記 5-0 の DB 確認）が先**。原因経路が分かる前の実装は過剰／的外れになるため提案に留める。

### 5-0. 原因確定のための DEV DB 確認（人手・SELECT のみ）

やまに青果スキーマに対し、該当の 3 行のメタデータを確認する（値の生転記は禁止、件数・パターンのみ報告）:

```sql
-- shipping_date=2026-09-23 の当該原体の全レコード
SELECT year, ticket_id, saving_id, material_id, standard_id,
       quantity, quantity_per_package, quantity_per_unit,
       staff_name, created_at, updated_at
FROM   <yamani_schema>.order_ledger
WHERE  shipping_date::date = '2026-09-23'
  AND  material_id = '<対象原体>'
ORDER  BY saving_id;
```

判定の指針:
- 3 行の `created_at` が同一 → **登録時に 3 行として作成された**（原因は登録経路／取込元データ）。
- `created_at` が異なり一部だけ `updated_at` が新しい → **後から行が追加された**（別経路の追記＝二重計上を疑う）。
- `staff_name` が `'CustomerApp'`（モバイル送信）/ 取込 / 受注入力のどれか → 発生経路が特定できる。

### 5-A. 分割が「取込元データ由来」だった場合（登録時 3 行）

- 取込元（SMART-AI 読取 or モバイル送信ペイロード）が同一原体を複数明細に分けている箇所を是正する。
  SO 側は 1:1 で忠実に保存しているだけなので、**SO の保存ロジック修正は不要**。

### 5-B. 分割が「未特定の編集経路」由来だった場合

- 「S-MOBILE モバイル管理」で数量修正する実画面の正確な遷移・呼び出し API を特定し、
  その経路が delete→再作成や按分を行っていれば、`mobile_order_modify` と同様の
  **その場 `bulk_update`** に寄せる（新規行を増やさない）。

### 5-C. 恒久対策（共通）

- 加工指示書で同一 `(client_id, end_destination_id, material_id, standard_id)` が端数で複数行に
  なる状態を検知する軽量ガード（警告表示）を検討。ただし根治は原因経路の是正であり、
  表示側の合算は数量の意味を変えるため安易に入れない。

---

## 事実と推測の分離（まとめ）

- **事実**: 加工指示書 `get_mounting_data` は `OrderLedger` を集約せず返す（13442- で annotate/aggregate/GROUP BY 0 件）。表示 JS の rowKey=`year|saving_id`（1 saving_id = 1 行）。`mobile_order_modify` は bulk_update のみで本体に create/delete/bulk_create 0 件。`OrderLedger` 作成経路は 3 本で全て 1:1。BOM 按分は `BomPurchase` 行き（bom_purchase.py:353）・修正では非トリガ。`quantity` は FloatField（models.py:467）で 2 桁量子化。298.87+0.57+0.56=300.00。
- **推測**: 3 行は受注登録時点で既に別レコードだった可能性が最も高い。原因経路（取込元 or 未特定の編集経路）の確定には DEV DB SELECT と実画面再現が必要。
- **参照保留**: SS 在庫引当（ツリー外・未参照）、「S-MOBILE モバイル管理」実画面の正確な API 経路（認証ゲート裏・未再現）。

## 本調査で確認できなかったこと（人手承認が必要な残作業 → REVIEW）

1. DEV DB の該当 3 行の `created_at`/`updated_at`/`staff_name`/`ticket_id`（この repo に DB 接続手段・資格情報が無い。`psql`/`pg_dump` 不在、接続設定も非存在を兄弟 [1/3] で実測確認済み）。
2. 実際の「S-MOBILE モバイル管理」画面での数量修正 → 加工指示書分割の再現（認証ゲート裏）。

---

**コード変更なし**（本タスクは調査・報告のみ。SO/SS を含むアプリコード・DB・Migration を一切変更していない）
