# ステップ5 学習まとめ

使用データ: `SNOWFLAKE_SAMPLE_DATA.TPCDS_SF10TCL`（小売業の取引データ）

---

## ステップ5: incrementalモデルを試す

### 目的

大量データの差分更新パターンを覚える。`is_incremental()` の仕組みと、コストを抑えながら検証する考え方を身につける。

### 設計方針

既存の `stg_store_sales`（1日分に固定）とは別に、検証専用の `stg_store_sales_incremental` を新設した。

- **日付範囲**: 複数日（2002-01-03〜01-05）に段階的に広げられるよう `var(max_date_sk)` で上限を可変にする
- **店舗を1店に絞る**: `STORE_SALES` は1日・全店で約870万行あるため、`ss_store_sk = 502` の1店舗のみに絞り、1日あたり約1.1万〜1.5万行まで縮小
- **unique_key**: `STORE_SALES` の粒度は「1チケット内の1商品明細」＝ `ss_ticket_number + ss_item_sk`。単一カラムでは重複しうるため複合キーを採用（事前に `count(*)` と `count(distinct ticket_number || '-' || item_sk)` が一致することを確認して裏付けた）

### stg_store_sales_incremental.sql

```sql
{{ config(materialized='incremental', unique_key=['ticket_number', 'item_sk']) }}

with source as (
    select * from {{ source('tpcds', 'STORE_SALES') }}
    where ss_store_sk = 502
      and ss_sold_date_sk between 2452278 and {{ var('max_date_sk') }}
      {% if is_incremental() %}
      and ss_sold_date_sk > (select max(sold_date_sk) from {{ this }})
      {% endif %}
),

renamed as (
    select
        ss_sold_date_sk  as sold_date_sk,
        ss_item_sk       as item_sk,
        ss_customer_sk   as customer_sk,
        ss_ticket_number as ticket_number,
        ss_quantity      as quantity,
        ss_sales_price   as sales_price,
        ss_net_paid      as net_paid
    from source
)

select * from renamed
```

- `2452278` は `2002-01-03` の `d_date_sk`（TPCDSでは日付ごとに連番）。範囲の下限を固定することで「その日までの全履歴」を巻き込まないようにしている
- `is_incremental()` が真のとき（＝対象テーブルが既に存在するとき）だけ、既存データの最大日付より後の行に絞る条件が追加される

### schema.ymlへのテスト追加

複合キーの一意性は `unique`/`not_null` では表現できないため、`dbt_utils.unique_combination_of_columns` を使用（`dbt-labs/dbt_utils` を `packages.yml` に追加し `dbt deps` でインストール）。

```yaml
  - name: stg_store_sales_incremental
    data_tests:
      - dbt_utils.unique_combination_of_columns:
          arguments:
            combination_of_columns:
              - ticket_number
              - item_sk
```

### 段階実行での検証結果

`var(max_date_sk)` を広げながら3回実行し、差分マージの挙動を確認した。

| 実行 | `max_date_sk` | 対象日 | 追加された行数 | 累計行数 |
|---|---|---|---|---|
| 1回目（full-refresh後） | 2452278 | 01/03 | 15,085 | 15,085 |
| 2回目 | 2452279 | 01/03〜01/04 | 11,965 | 27,050 |
| 3回目 | 2452280 | 01/03〜01/05 | 11,951 | 39,001 |
| 冪等性確認（3回目と同条件で再実行） | 2452280 | 01/03〜01/05 | 0（変化なし） | 39,001 |

`select sold_date_sk, count(*) from {{ ref('stg_store_sales_incremental') }} group by 1 order by 1` で日別件数を見ながら、新しい日の分だけが追加され、既存日は変化しないことを確認した。同じ条件で再実行しても行数が増えないことから、`unique_key` によるMERGEが正しく重複を防いでいることも確認できた。

---

## Tips: 詰まったポイント・質問した内容

### 1. `<=` だけの日付フィルタが過去全履歴を巻き込んだ

**詰まった内容**: 最初の実装は `ss_sold_date_sk <= {{ var('max_date_sk') }}` のみで、下限を設けていなかった。1店舗・1日分（約1.5万行）を想定していたが、初回実行が**5分21秒**かかり、**28,738,807行**（2,873万行）が作成されてしまった。

**原因**: `STORE_SALES` のデータは2002-01-03よりずっと前（データ開始時点）から存在する。`<=` 条件だけでは「データ開始〜指定日」までの**全期間**が対象になってしまい、店舗を絞っていても数年分の売上を読み込む形になっていた。

**修正**: `between 2452278 and {{ var('max_date_sk') }}` のように下限を固定し、範囲を明示的に区切ることで解決。修正後は初回実行が1.38秒・15,085行と想定通りになった。

**教訓**: incrementalモデルの「初回フルビルド」を設計するときは、上限だけでなく下限（どこから取り始めるか）も明示しないと、意図しない量のデータを読み込むことがある。特に長期間蓄積されたテーブルでは要注意。

### 2. 誤って作られた巨大テーブルは `--full-refresh` で作り直す必要がある

**詰まった内容**: 上記のバグで一度2,873万行のテーブルができてしまった後、SQLを修正しただけでは直らなかった（`is_incremental()` の差分ロジックは「既存データより新しい行を追加する」だけなので、既に入っている誤った行はそのまま残る）。

**対応**: `dbt run --full-refresh` でテーブルを作り直し、正しい行数（15,085行）になることを確認した。

**教訓**: incrementalモデルのロジックを変更した後は、既存テーブルが新しいロジックと整合しているとは限らない。ロジック変更時は `--full-refresh` で作り直すのが安全。

### 3. `dbt compile` で `is_incremental()` の展開結果を事前確認できる

初回実行前に `dbt compile --select stg_store_sales_incremental --vars '{max_date_sk: 2452278}'` を実行し、`target/compiled/` 配下の生成SQLを確認したところ、`is_incremental()` ブロックの中身が空になっている（＝テーブルがまだ存在しないためFalse判定）ことが見えた。実行前に「今回はフルビルドになる／差分ロジックが効く」のどちらかをSQLレベルで確認できるのは有用だった。

### 4. `--vars` はYAML/JSON形式の文字列で渡す

```bash
dbt run --select stg_store_sales_incremental --vars '{max_date_sk: 2452278}'
```

シングルクォートで囲み、中身は `{key: value}` の形式。モデル側では `{{ var('max_date_sk') }}` で参照する。

---

## ステップ6（今後追記予定）
