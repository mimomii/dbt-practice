# ステップ1・ステップ2 学習まとめ

使用データ: `SNOWFLAKE_SAMPLE_DATA.TPCDS_SF10TCL`（小売業の取引データ）

---

## ステップ1: stagingモデル

### 目的

ソーステーブルをそのまま軽くクリーニングする1:1モデルを作る。

### 作成したモデル

| モデル名 | ソーステーブル | 内容 |
|---|---|---|
| `stg_customer` | `CUSTOMER` | 顧客マスタ |
| `stg_store_sales` | `STORE_SALES` | 店舗売上明細 |
| `stg_item` | `ITEM` | 商品マスタ |
| `stg_date_dim` | `DATE_DIM` | 日付ディメンション |

### source() 関数

Snowflakeなどの**生のソーステーブル**を参照するときに使う。

```sql
{{ source('tpcds', 'CUSTOMER') }}
-- コンパイル後: SNOWFLAKE_SAMPLE_DATA.TPCDS_SF10TCL.CUSTOMER
```

- 第1引数: `sources.yml` に定義したソース名
- 第2引数: テーブル名
- **使う場所**: stagingモデルだけ（生データに最初に触れる層）

### sources.yml

`source()` 関数が参照する定義ファイル。`models/staging/` に配置する。

```yaml
sources:
  - name: tpcds
    database: SNOWFLAKE_SAMPLE_DATA
    schema: TPCDS_SF10TCL
    tables:
      - name: CUSTOMER
      - name: STORE_SALES
```

### stagingモデルの書き方

CTEを使って `source → renamed` の2段構成で書くのが定番。

```sql
with source as (
    select * from {{ source('tpcds', 'CUSTOMER') }}
),
renamed as (
    select
        c_customer_sk   as customer_sk,
        c_customer_id   as customer_id,
        c_first_name    as first_name,
        c_last_name     as last_name,
        c_email_address as email_address
    from source
)
select * from renamed
```

---

## ステップ2: intermediateモデル

### 目的

複数のstagingモデルをJOIN・集計して中間テーブルを作る。

### 作成したモデル

| モデル名 | 内容 |
|---|---|
| `int_sales_with_customer` | 売上に顧客・商品情報をJOIN |
| `int_daily_sales` | 日別の売上集計 |

### ref() 関数

**自分が作ったモデル**（.sqlファイル）を参照するときに使う。

```sql
{{ ref('stg_store_sales') }}
-- コンパイル後: DEV_DB.DEV_SCHEMA.stg_store_sales
```

- 引数: 参照したいモデルのファイル名（`.sql` は不要）
- **使う場所**: intermediate・martsモデル（stagingの成果物を使う層）

### source() と ref() の使い分け

```
SNOWFLAKE（生テーブル）
    ↓  source()
stg_*** （stagingモデル）
    ↓  ref()
int_*** （intermediateモデル）
    ↓  ref()
mart_*** （martsモデル）
```

### ref() を使う理由

- **依存関係の自動解決**: dbtが実行順序を自動で決める
- **環境の自動切り替え**: dev/prodで異なるスキーマを使っても1箇所で管理できる
- **リネージグラフへの反映**: どのモデルがどれに依存しているか可視化される

### JOINモデルの書き方（int_sales_with_customer）

```sql
select
    ss.sold_date_sk,
    ss.ticket_number,
    ss.quantity,
    ss.sales_price,
    ss.net_paid,
    c.first_name,
    c.last_name,
    i.item_desc,
    i.category,
    i.brand
from {{ ref('stg_store_sales') }} ss
left join {{ ref('stg_customer') }} c
    on ss.customer_sk = c.customer_sk
left join {{ ref('stg_item') }} i
    on ss.item_sk = i.item_sk
```

- `LEFT JOIN` を使うことで、顧客・商品が紐づかない売上レコードも落とさない
- テーブルエイリアス（`ss`, `c`, `i`）で可読性を上げる

### 集計モデルの書き方（int_daily_sales）

```sql
select
    dd.date_day,
    dd.year,
    dd.month_of_year,
    sum(ss.net_paid)  as total_net_paid,
    sum(ss.quantity)  as total_quantity,
    count(*)          as order_count
from {{ ref('stg_store_sales') }} ss
left join {{ ref('stg_date_dim') }} dd
    on ss.sold_date_sk = dd.date_sk
group by dd.date_day, dd.year, dd.month_of_year
```

- `GROUP BY` には集計しない全カラムを列挙する
- カラムのテーブル所属（エイリアス）を `SELECT` と `GROUP BY` で一致させる

### dbt_project.yml へのフォルダ設定追加

新しいフォルダ（`intermediate/`）を追加したら `dbt_project.yml` にも設定を追記する。

```yaml
models:
  dbt_practice:
    staging:
      +materialized: view
    intermediate:
      +materialized: view
```

---

## よく使ったコマンド

```bash
# SQLの文法チェック（Snowflakeに接続せず検証）
dbt compile --select <モデル名>

# フォルダ単位で実行
dbt run --select intermediate

# 特定モデルを指定して実行
dbt run --select int_sales_with_customer int_daily_sales
```

- `dbt compile` で文法エラーを確認してから `dbt run` する習慣をつける
- `dbt run` はプロジェクトルート（`dbt_project.yml` があるフォルダ）で実行する
