# ステップ3・ステップ4 学習まとめ

使用データ: `SNOWFLAKE_SAMPLE_DATA.TPCDS_SF10TCL`（小売業の取引データ）

---

## ステップ3: martsモデル

### 目的

intermediateモデルをもとに、BIツールに公開する最終集計テーブルを作る。

### 作成したモデル

| モデル名 | 内容 |
|---|---|
| `mart_customer_summary` | 顧客別の購買サマリー（総購入額・数量・注文回数） |
| `mart_monthly_sales` | 月別の売上サマリー |

### mart_customer_summary.sql

```sql
select
    customer_id,
    first_name,
    last_name,
    sum(net_paid) as total_net_paid,
    sum(quantity) as total_quantity,
    count(distinct ticket_number) as order_count
from {{ ref('int_sales_with_customer') }}
group by
    customer_id,
    first_name,
    last_name
```

- `count(distinct ticket_number)` — 同じ伝票番号の重複行を注文1件として数えるため `distinct` を使う

### mart_monthly_sales.sql

```sql
select
    year,
    month_of_year,
    sum(total_net_paid) as total_net_paid,
    sum(total_quantity) as total_quantity,
    sum(order_count) as order_count
from {{ ref('int_daily_sales') }}
group by year, month_of_year
```

- 日別集計（`int_daily_sales`）をさらに月単位に集計し直す構造

### dbt_project.yml への追加

```yaml
models:
  dbt_practice:
    staging:
      +materialized: view
    intermediate:
      +materialized: view
    marts:
      +materialized: view
```

---

## Tips: 詰まったポイント・質問した内容

### 1. `dbt compile` はDBに接続していない → カラム名の誤りは検出できない

**詰まった内容**: `int_sales_with_customer.sql` で `ss.c_customer_sk`（存在しないカラム）を参照していたが、`dbt compile` はエラーにならなかった。

**理由**: `dbt compile` はJinja（`ref()`/`source()`/`config()`）をSQLに展開し、依存関係を解決するだけで、**Snowflakeに実際にSQLを投げない**。カラム名やテーブル構造まではチェックしない。実際にDBへ実行する `dbt run` の段階で初めて "invalid identifier" のようなエラーとして表面化する。

```
dbt compile = SQLの組み立て・依存関係の整合性チェック（DB接続なし）
dbt run     = 実際にSnowflakeで実行 → カラム名・型などの実行時エラーもここで判明
```

**教訓**: `compile` が通ってもデータベース的に正しいとは限らない。`run` まで通して初めて確認できる。

### 2. サロゲートキー(`_sk`)とビジネスキー(`_id`)の混同

**詰まった内容**: `ss.c_customer_sk as customer_id` のように、存在しないカラム名の誤字に加えて、そもそも `customer_sk`（結合用の内部キー）と `customer_id`（顧客の業務上のID）を混同していた。

**修正**: すでに `stg_customer`（alias `c`）とJOIN済みなので、`c.customer_id` を使うのが正しい。JOIN先のテーブルにビジネスキーがある場合はそちらを使う、という基本を再確認。

### 3. `dbt run` は変更差分を見ない

**質問**: 「コードを変更していないSQLは更新のイメージで合っているか？」

**回答**: dbtはデフォルトで「SQLが変わったかどうか」を判定して実行をスキップする仕組みは持たない（`state:modified` という別機能はある）。`dbt run` を実行すると対象モデルは**毎回すべて実行**される。ただし `view` は `CREATE OR REPLACE VIEW` というメタデータ操作のみなので、実質コストはほぼゼロ。

### 4. マテリアライゼーションの種類とコスト

**質問**: 「Tableに設定するにはどこを変更するか、他に選択肢はあるか」

| 設定値 | 特徴 |
|---|---|
| `view`（デフォルト） | クエリ定義を保存するだけ。実行コストほぼゼロ |
| `table` | 実データとして保存。**毎回全件再計算 = warehouse計算コストがかかる** |
| `incremental` | 差分のみ追加。大量データ向け（ステップ5で学習予定） |
| `ephemeral` | DB上に何も作らずCTEとして埋め込まれる |
| `dynamic_table` | Snowflake固有。ダイナミックテーブル機能を利用 |

設定場所は2通り:
- モデル単体: `{{ config(materialized='table') }}` をSQL先頭に追記
- フォルダ単位: `dbt_project.yml` の該当セクションに `+materialized: table`

### 5. Gitワークフロー: ブランチを切り忘れて `main` に直接コミットした

**詰まった内容**: 本来 `step3-marts` のような作業ブランチを切ってから作業すべきだったが、`git checkout -b` を実行せずに `main` へ直接コミットしてしまった。`git push -u origin step3-marts` を実行した際に以下のエラーが発生:

```
error: src refspec step3-marts does not match any
```

（ローカルに `step3-marts` ブランチ自体が存在しないため）

**修正方法**: まだ `origin` にpushしていなかったため、コミットを失わずに退避できた。

```bash
# 現在のmain（該当コミット込み）を指す新規ブランチを作成
git branch step3-marts

# mainを、対象コミットの1つ前まで巻き戻す（作業ツリーはclean前提）
git reset --hard <1つ前のコミットハッシュ>

# 状態確認
git branch -vv

# 新規ブランチをpush
git push -u origin step3-marts
```

**教訓**:
- `git reset --hard` は破壊的操作だが、**先に `git branch` で退避ブランチを作ってから**実行すれば、コミット自体は失われない
- pushしていない限り、ローカルでのブランチ再編成はやり直しがきく。焦って `main` を直接pushしないよう、`git status` / `git branch -vv` で都度状態確認する習慣が有効

### 6. `git push -u origin <ブランチ名>` はブランチ名を省略できるか

**質問**: 「ブランチ名はなくても作動する？」

**回答**: 追跡設定（upstream）が既に済んでいるブランチであれば `git push` だけで動く（`git branch -vv` で `[origin/main: ahead N]` のように表示されていれば設定済み）。`-u` は初回にリモートとの紐付けを作るためのオプションなので、ブランチ名の省略は基本的にできない（現在のブランチを対象にしたい場合は `git push -u origin HEAD` という書き方はある）。

---

## よく使ったコマンド

```bash
# 特定モデルとその上流を実行
dbt run --select +mart_customer_summary

# コンパイル結果（展開後SQL）を直接確認
cat dbt_practice/target/compiled/dbt_practice/models/marts/mart_customer_summary.sql

# 詳細ログを確認
tail -n 40 dbt_practice/logs/dbt.log

# PR作成
gh pr create --base main --head <ブランチ名> --title "..." --body "..."
```

---

## ステップ4: テストを書く

### 目的

データ品質テストの書き方を覚える。ビルトインテスト（schema.yml）とカスタムSQLテスト（tests/フォルダ）の2種類を実装する。

### ビルトインテスト（schema.yml）

`models/staging/schema.yml` と `models/marts/schema.yml` を新規作成し、主要カラムにテストを追加した。dbt 1.8以降の推奨構文である `data_tests:`（旧`tests:`のエイリアス）で統一。

```yaml
version: 2

models:
  - name: stg_customer
    columns:
      - name: customer_sk
        data_tests:
          - unique
          - not_null
      - name: customer_id
        data_tests:
          - unique
          - not_null

  - name: stg_store_sales
    columns:
      - name: customer_sk
        data_tests:
          - relationships:
              arguments:
                to: ref('stg_customer')
                field: customer_sk
```

marts側では `accepted_values` も使用:

```yaml
  - name: mart_monthly_sales
    columns:
      - name: month_of_year
        data_tests:
          - not_null
          - accepted_values:
              values: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]
```

### カスタムSQLテスト（tests/フォルダ）

`tests/` に `.sql` ファイルを置くと、そのSELECT文が「**0行ならPASS、1行以上返ればFAIL**」というカスタムテスト（singular test）になる。ビルトインでは表現しづらい業務ルールの検証に使う。

```sql
-- tests/assert_store_sales_quantity_not_negative.sql
select *
from {{ ref('stg_store_sales') }}
where quantity < 0
```

作成した5件（`quantity`/`sales_price`/`current_price` のマイナスチェック、`order_count`が1件以上か、`total_net_paid`のマイナスチェック）はすべてPASS。カスタムテストのみをまとめて実行する場合は次のセレクタを使う:

```bash
dbt test --select test_type:singular
```

---

## Tips: 詰まったポイント・質問した内容（ステップ4）

### 1. schema.ymlで同じモデル名を2回定義するとエラーになる

**詰まった内容**: `stg_customer` や `stg_date_dim` を別ブロックとして2回書いてしまい、dbtが「同じモデルに対するエントリが2つある」というエラーで落ちた。

**教訓**: 1モデル1ブロックにまとめ、`columns:` の下に複数カラムを並べる。

### 2. `relationships` テストのYAMLインデントミス

**詰まった内容**:
```yaml
data_tests:
  - relationships:
    to: ref('stg_customer')
    filed: customer_sk
```
`to:` が `relationships:` と同じインデント幅になっていたため、`relationships` の子ではなく兄弟キーとして解釈されてしまっていた。加えて `field` を `filed` とタイポしていた。

**教訓**: ネストするキーは親キーよりも深くインデントする。YAMLはインデントの誤りがあっても構文エラーにならず「意図と違う構造」として解釈されてしまうことがあるので、レビュー時に注意が必要。

### 3. `relationships` テストを存在しないカラムに定義してしまった

**詰まった内容**: `item_sk` に対する `relationships` テストを、誤って `stg_date_dim`（`item_sk`というカラムを持たない）の下に書いてしまっていた。正しくは `stg_store_sales.item_sk` に定義すべきだった。

**教訓**: テストはモデルの実際のカラム構成を確認してから追加する。コピペで似た構造を量産すると、参照先の取り違えが起きやすい。

### 4. dbt 1.11での非推奨警告: `relationships` の引数は `arguments:` の下にネストする

```
[WARNING][MissingArgumentsPropertyInGenericTestDeprecation]
Found top-level arguments to test `relationships` ...
Arguments to generic tests should be nested under the `arguments` property.
```

`to`/`field` をトップレベルに書く旧構文はまだ動くが非推奨。将来のdbtバージョンでエラーになる可能性があるため、`arguments:` の下にネストする新構文に修正した。

### 5. `dbt test` が14分経っても終わらない → 巨大テーブルのフルスキャンが原因だった

**詰まった内容**: `mart_customer_summary` の `not_null` テストが10分以上終わらなかった。

**調査方法**: `Ctrl+C` で中断後、Snowflakeで以下を実行してクエリ履歴を直接確認した。

```sql
select query_id, query_text, execution_status, warehouse_name,
       start_time, end_time, total_elapsed_time / 1000 as elapsed_seconds, bytes_scanned
from table(information_schema.query_history_by_user(user_name => current_user(), result_limit => 10))
order by start_time desc;
```

（`partitions_scanned`/`partitions_total` は `INFORMATION_SCHEMA` の関数には存在せず、`ACCOUNT_USAGE` 側のみだったのでエラーになった）

**判明した内容**: `Ctrl+C` → dbtが `system$cancel_all_queries` を発行し正常にキャンセルされていたが、キャンセルまでの840秒で **891GB** をスキャンしていた。原因は `mart_customer_summary` がviewで、参照元の `SNOWFLAKE_SAMPLE_DATA.TPCDS_SF10TCL.STORE_SALES` が10TBクラスの巨大テーブルだったこと。

**教訓**: サンプルデータでも実際のテーブルサイズを確認せずに演習を進めると、意図せず高コスト・長時間のクエリを引き起こす。`dbt compile` は通っても実行時間・コストは別問題として確認する必要がある。

### 6. Snowsightで「クエリの詳細は利用できません」と表示される場合がある

**詰まった内容**: キャンセルしたクエリの詳細プロファイルをSnowsight画面から見ようとしたが、「クエリ履歴は、短時間のハイブリッドワークロードジョブのクエリの詳細やプロファイルを提供しません」と表示され見れなかった。

**対処**: 画面のプロファイルに頼らず、`INFORMATION_SCHEMA.QUERY_HISTORY_BY_USER()` をSQLで直接叩けば、実行時間・スキャンバイト数などの実行統計は確認できる。

### 7. データ量を段階的に絞り込んだ経緯

**やったこと**: `stg_store_sales.sql` に `WHERE ss_sold_date_sk IN (SELECT d_date_sk FROM ... WHERE ...)` で絞り込みを追加。ただし何年・何ヶ月分のデータがあるか事前にはわからなかったため、件数を確認しながら段階的に絞り込んだ。

| 絞り込み単位 | 件数 |
|---|---|
| `d_year = 2025` | 0件（存在しない年だった） |
| `d_year = 2002` | 5,500,490,115件（55億件） |
| `d_year = 2002, d_moy = 1` | 321,532,511件（3.2億件） |
| `d_date = '2002-01-03'`（1日） | 8,728,966件（約870万件） |

最終的に日付1日分まで絞り込むことで、`dbt run` が5.9秒、`dbt test` が11秒程度まで短縮された（絞り込み前は14分でもキャンセルするまで終わらなかった）。

**教訓**: `SNOWFLAKE_SAMPLE_DATA` のような「サンプル」データでも、スケールファクター次第では本番相当かそれ以上のサイズになる。練習用途では最初から日単位など小さい粒度で絞り込んでおくのが安全。また、1/1・1/2のような特異日（データ生成上のイベント日）は件数が偏ることがあるので、平常時に近い日を選ぶとよい。

### 8. `customer_id` がNULLになる集計行が発生した理由

**詰まった内容**: NULL除外前は `mart_customer_summary` の `not_null` テストが1件だけ失敗していた。

**原因**: `stg_store_sales.customer_sk` にNULLの行が存在し（匿名取引などの可能性）、`LEFT JOIN` を経て `customer_id` もNULLのまま残っていた。`GROUP BY customer_id` はNULLを1つのグループとして扱うため、複数のNULL行が集約されて「1件のNULL customer_id行」としてテストに引っかかった。

**対応**: `mart_customer_summary.sql` に `where customer_id is not null` を追加し、「顧客が特定できる売上のみを集計する」という意味を明確にした上でテストを維持する方針にした。

**教訓**: `GROUP BY` はNULLを弾かない。集計系のmartモデルでは、集約前にNULLキーをどう扱うか（除外するか、"不明"として残すか）を意識して設計する必要がある。
