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

### 目的

差分更新戦略のバリエーションと軽量な中間モデルの使い所を覚える。

### Part A: incremental_strategyの比較（merge vs delete+insert）

`stg_store_sales_incremental`を対象に、`incremental_strategy`を明示指定して2種類の戦略を比較した。

#### incremental_strategyとは

dbtのincrementalマテリアライゼーションは「新しい行だけを既存テーブルに反映する」という考え方だが、**その反映の仕方（SQL文の組み立て方）**には複数の実装方式がある。これが`incremental_strategy`。

**merge（Snowflakeのデフォルト）**

```sql
merge into 本番テーブル as DEST
using 差分バッチの一時テーブル as SRC
on (DEST.ticket_number = SRC.ticket_number) and (DEST.item_sk = SRC.item_sk)
when matched then update set ...   -- キーが一致する行は上書き
when not matched then insert ...   -- 一致しない行は新規追加
```

`unique_key`で指定したキーが一致するかどうかを1つのSQL文の中で判定し、一致すればUPDATE、しなければINSERTを行う。1トランザクションで完結し、SnowflakeのようなMERGE文最適化が効くDBでは標準的な選択。

**delete+insert**

```sql
delete from 本番テーブル where (ticket_number, item_sk) in (差分バッチに含まれるキー一覧);
insert into 本番テーブル select * from 差分バッチの一時テーブル;
```

判定と反映を2つのSQL文に分けて行う。「キーが一致する行を消してから、新しいデータを丸ごと入れ直す」という考え方で、MERGE文をうまくサポートしない・パフォーマンスが出ないDB向けの互換性重視の戦略として用意されている。

#### 検証手順

1. `config`に`incremental_strategy='merge'`を明示指定
2. `--full-refresh`→`--vars '{max_date_sk: 2452278}'`で初回実行→`{max_date_sk: 2452280}`で差分実行
3. `target/run/`配下の実行SQLを確認 →`merge into ... when matched ... when not matched ...`の1文構成
4. `incremental_strategy='delete+insert'`に変更し、同じ手順（full-refresh→初回→差分）を再実施
5. `target/run/`配下の実行SQLを確認 →`delete from ... where (ticket_number, item_sk) in (...)`→`insert into ...`の2文構成
6. `dbt show --inline "select count(*) from {{ ref('stg_store_sales_incremental') }}"`で行数を比較
7. `merge`に戻して`--full-refresh`＋`dbt test`で最終確定

#### 結果

| ストラテジー | 実行SQLの構成 | 最終行数 |
|---|---|---|
| `merge` | `MERGE INTO`1文（`when matched`/`when not matched`） | 39,001 |
| `delete+insert` | `DELETE`→`INSERT`の2文 | 39,001 |

両ストラテジーで最終行数は一致した。最終的に`merge`を採用して確定。

#### なぜ今回、両方とも最終行数が同じだったのか

今回のデータは「新しい日付の行が追加されるだけ」で、既存の行の中身が変わる更新（同じキーで値だけ変わるケース）は発生しない。そのため、`merge`は該当キーが存在せず全て`insert`側の処理になり、`delete+insert`も削除対象がなく実質`insert`だけが効く状態になる。**今回のシナリオでは挙動の差が結果に表れなかった**。両者の違いが実際に効いてくるのは「既存キーの値そのものが変わる更新（例: 後から金額が修正された等）」があるケース。

#### dbtが裏で行っていること（`__dbt_tmp`）

実行SQLを見ると、`stg_store_sales_incremental__dbt_tmp`という一時テーブルが登場する。dbtはモデルのSELECT文（差分抽出クエリ）の結果を一旦この一時テーブルに書き出し、それを`merge`または`delete+insert`で本番テーブルに反映する、という2段階の仕組みになっている。

### Part B: ephemeral化

`int_store_sales_enriched`（stg_store_salesにcustomer・itemをLEFT JOINするだけの単純なモデルで、`fct_customer_summary`からしか参照されていない）を対象にephemeral化した。

#### ephemeralとは

`view`や`table`のようにSnowflake上に実体（オブジェクト）を作らず、参照元のモデルのSQLに**CTEとして埋め込まれる**マテリアライゼーション。単独では実行できず（実体を持たないため）、必ず依存先のモデル経由でのみコンパイル・実行される。

```sql
{{ config(materialized='ephemeral') }}

select
    ss.sold_date_sk,
    ...
```

#### 検証結果

`dbt compile --select fct_customer_summary`の結果、`int_store_sales_enriched`が独立したview参照ではなく`__dbt__cte__int_store_sales_enriched`という名前のCTEとして展開された。

```sql
with __dbt__cte__int_store_sales_enriched as (
    select
        ss.sold_date_sk,
        ...
    from DBT_PRACTICE.DEV.stg_store_sales ss
    left join DBT_PRACTICE.DEV.stg_customers c
        on ss.customer_sk = c.customer_sk
    left join DBT_PRACTICE.DEV.stg_items i
        on ss.item_sk = i.item_sk
) select
    customer_id,
    ...
from __dbt__cte__int_store_sales_enriched
where customer_id is not null
group by ...
```

`dbt run --select int_store_sales_enriched`を単独実行すると、対象0件で何も作成されずに終了することを確認した（`Finished running  in ...`のようにモデル種別の記載自体がなく、`view`/`table`のように「作成された」というログが一切出ない）。

一方、`dbt run --select fct_customer_summary` / `dbt test --select fct_customer_summary`は問題なく成功し、全テストPASSした。

#### ephemeralの利点・制約

- **利点**: Snowflake上にオブジェクトを作らないため、ストレージやメタデータ管理の対象が減る。単純なJOIN・フィルタなど「それ自体を直接クエリしたいわけではない中間ステップ」に向く
- **制約**: 単独でクエリ・デバッグできない（依存先のコンパイル結果の中でしか実体を見られない）。複数のモデルから参照されるephemeralモデルがある場合、参照される都度CTEとして重複展開されるため、重い処理をephemeral化すると逆に非効率になりうる（今回のように単純なJOINで参照元が1つだけ、という条件が向いている）

#### 後片付け

ephemeral化した時点でSnowflake上にviewとして作る対象ではなくなるため、既存の`int_store_sales_enriched`view（リネーム直後の検証で作成したもの）をSnowsightから手動`drop view`した。
