# ステップ7・ステップ8 学習まとめ

使用データ: `SNOWFLAKE_SAMPLE_DATA.TPCDS_SF10TCL`（小売業の取引データ）

---

## ステップ7: カスタムマクロを作る

### 目的

再利用可能なJinjaマクロの書き方を覚える。既存モデルの重複コードをマクロ化してDRYにする、または新規に共通処理を切り出す。

### 設計方針

計画段階でコードを見直し、以下3つのマクロを作成する方針にした。

| マクロ名 | 種別 | 目的 |
|---|---|---|
| `store_sales_columns()` | 重複解消 | `stg_store_sales` / `stg_store_sales_incremental` の `renamed` CTEで完全に重複していたカラムリネームを共通化 |
| `limit_by_date_range(date_column, start_date_sk, end_date_sk)` | 引数化 | 両モデルの「コスト対策の絞り込み」は条件の形が違ったため、`date_sk`レンジ絞り込み部分だけを引数付きマクロとして共通化 |
| `round_money(column_name, decimal_places=2)` | 新規導入 | 既存の重複ではなく、金額カラムの表示桁数を揃える処理を新規にマクロ化 |

### 1. store_sales_columns()

```sql
{% macro store_sales_columns() -%}
    ss_sold_date_sk  as sold_date_sk,
    ss_item_sk       as item_sk,
    ss_customer_sk   as customer_sk,
    ss_ticket_number as ticket_number,
    ss_quantity      as quantity,
    ss_sales_price   as sales_price,
    ss_net_paid      as net_paid
{%- endmacro %}
```

呼び出し側（`stg_store_sales.sql` / `stg_store_sales_incremental.sql`共通）:

```sql
renamed as (
    select
        {{ store_sales_columns() }}
    from source
)
```

### 2. limit_by_date_range()

```sql
{% macro limit_by_date_range(date_column, start_date_sk, end_date_sk) -%}
    {{ date_column }} between {{ start_date_sk }} and {{ end_date_sk }}
{%- endmacro %}
```

`stg_store_sales.sql`はそれまで `DATE_DIM` をサブクエリで引いて `d_date = '2002-01-03'` という条件で1日分に絞っていたが、`d_date_sk`が判明していれば直接指定できるため、サブクエリごと廃止して単純化した。

```sql
where {{ limit_by_date_range('ss_sold_date_sk', 2452278, 2452278) }}
```

`stg_store_sales_incremental.sql`側は、店舗絞り込み条件とマクロを組み合わせる形にした。

```sql
where ss_store_sk = 502
  and {{ limit_by_date_range('ss_sold_date_sk', 2452278, var('max_date_sk')) }}
  {% if is_incremental() %}
  and ss_sold_date_sk > (select max(sold_date_sk) from {{ this }})
  {% endif %}
```

単日絞り込みと日付レンジ絞り込みという見た目の異なる2つの条件を、「開始・終了date_skを引数で受け取る」という1つの抽象で表現できることを確認した（単日の場合は開始と終了に同じ値を渡す）。

### 3. round_money()

```sql
{% macro round_money(column_name, decimal_places=2) -%}
    round({{ column_name }}, {{ decimal_places }})
{%- endmacro %}
```

`mart_monthly_sales.sql` / `mart_customer_summary.sql` の `total_net_paid` に適用。

```sql
{{ round_money('sum(total_net_paid)') }} as total_net_paid
```

集計式（`sum(...)`）をそのまま文字列で渡せる、という汎用マクロの作り方を確認できた。

### 検証結果

各マクロ導入後、`dbt compile` でコンパイル結果が元のSQLと同じ内容に展開されることを確認し、`dbt run` / `dbt test` を実行して全件PASSであることを確認した。

| 対象モデル | run | test |
|---|---|---|
| `stg_store_sales` / `stg_store_sales_incremental`（マクロ1・2適用後） | SUCCESS | PASS 5/5 |
| `mart_monthly_sales` / `mart_customer_summary`（マクロ3適用後） | SUCCESS | PASS 7/7 |

---

## Tips: 詰まったポイント・質問した内容（ステップ7）

### 1. マクロの説明は `{# #}` コメントだけでは `dbt docs` に反映されない

**詰まった内容**: 各マクロファイルの冒頭に `{# ... #}` 形式のJinjaコメントで説明を書いたが、`dbt docs generate && dbt docs serve` でドキュメントサイトを確認しても、マクロの説明が表示されなかった。

**原因**: `{# #}` はJinjaのコメント構文で、コンパイル時に単に読み飛ばされるだけのもの。モデルの `description` が `schema.yml` のYAMLプロパティとして管理されるのと同様に、マクロの説明も `schema.yml`（マクロパス配下の任意の `.yml`）に `macros:` セクションとして明示的に書く必要がある。

**修正**: `macros/schema.yml` を新規作成し、`macros:` トップレベルキーの下に `name` / `description` / `arguments`（引数ごとの `name` / `type` / `description`）を記載した。

```yaml
version: 2

macros:
  - name: limit_by_date_range
    description: >
      コスト対策として date_sk カラムを指定範囲に絞り込む where句断片。
    arguments:
      - name: date_column
        type: string
        description: 絞り込み対象の date_sk カラム名
      - name: start_date_sk
        type: integer
        description: 絞り込み範囲の開始 date_sk
      - name: end_date_sk
        type: integer
        description: 絞り込み範囲の終了 date_sk
```

再度 `dbt docs generate` したところ、サイドバーの「Macros」に説明と引数一覧が表示されることを確認した。

**教訓**: モデルは `{% docs %}` ブロック、マクロは `schema.yml` の `macros:` セクションと、ドキュメント化の入り口がオブジェクトの種類によって異なる。`{# #}` コメントはあくまでソースコードを読む人向けであり、ドキュメントサイトへの反映経路としては別物と理解しておく必要がある。

### 2. 異なる形のWHERE条件から共通の抽象を見つける

`stg_store_sales`（単日の等値条件）と`stg_store_sales_incremental`（店舗＋日付レンジ＋差分）は一見コードの形が違うため単純なコピペ抽出はできなかったが、「date_skを範囲で絞る」という考え方自体は共通していた。引数を持つマクロにすることで、見た目の異なる2つのSQLから共通の関心事だけを抜き出せることを確認できた。

---

## ステップ7完了時点の変更ファイル

- `dbt_practice/macros/store_sales_columns.sql`（新規作成）
- `dbt_practice/macros/limit_by_date_range.sql`（新規作成）
- `dbt_practice/macros/round_money.sql`（新規作成）
- `dbt_practice/macros/schema.yml`（新規作成、マクロのdescription）
- `dbt_practice/models/staging/stg_store_sales.sql`（マクロ適用、DATE_DIMサブクエリ廃止）
- `dbt_practice/models/staging/stg_store_sales_incremental.sql`（マクロ適用）
- `dbt_practice/models/marts/mart_monthly_sales.sql`（`round_money`適用）
- `dbt_practice/models/marts/mart_customer_summary.sql`（`round_money`適用）

---

## ステップ8: incrementalの発展とephemeral

（未着手。実施後にこのセクションへ追記する）
