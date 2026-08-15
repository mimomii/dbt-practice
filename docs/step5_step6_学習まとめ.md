# ステップ5・ステップ6 学習まとめ

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

## ステップ6: ドキュメントを生成する

### 目的

`dbt docs` でドキュメントサイトを生成・確認し、`description` の書き方とリネージグラフ（DAG）の読み方を身につける。

### やったこと

1. **description の追加**
   - `sources.yml`: source（`tpcds`）とテーブル4つ（CUSTOMER, STORE_SALES, ITEM, DATE_DIM）
   - `staging/schema.yml`: 5モデル全てにモデルレベルの説明、既存テスト対象カラムにカラムレベルの説明
   - `intermediate/schema.yml`: 新規作成（これまでファイル自体が存在せず未ドキュメント化だった）。`int_sales_with_customer` / `int_daily_sales` のモデル説明・全カラム説明を追加
   - `marts/schema.yml`: 2モデルのモデル説明・全カラム説明を追加
   - いずれも既存の `data_tests` ブロックは変更せず、`description` のみを追記する形で進めた
2. `dbt docs generate && dbt docs serve` でローカル確認し、description・リネージグラフの反映を確認
3. **docs block の演習**（`.md` + `{{ doc(...) }}`）
4. VSCode拡張機能 **dbt Power User** で `ref()` の定義ジャンプができない問題のトラブルシューティング

### docs block（再利用可能な説明文）

`models/docs.md` を新規作成し、複数モデルで使い回す説明文と、長文になる説明を切り出した。

```markdown
{% docs surrogate_key %}
ソーステーブルの主キーを内部的に採番した代理キー（サロゲートキー）。
自然キー（`customer_id`など）と異なり業務的な意味を持たず、モデル間のJOINキーとしてのみ使用する。
{% enddocs %}

{% docs stg_store_sales_incremental %}
店舗ID 502の売上明細を対象としたincrementalモデル。

- 初回実行時: `sold_date_sk` が `2452278`〜`var('max_date_sk')` の範囲を取り込む
- 2回目以降: `is_incremental()` が真になり、取り込み済みの最大`sold_date_sk`より新しいレコードのみを差分取得する
- `unique_key` に `['ticket_number', 'item_sk']` を指定しているため、同一キーの行は`MERGE`で上書きされ重複しない

検証の詳細は `docs/step5_step6_学習まとめ.md` を参照。
{% enddocs %}
```

`schema.yml` 側からは以下のように参照する。Jinjaの `{{ doc(...) }}` はYAML文字列の中でも展開されるため、前後に固定テキストを混ぜることも可能。

```yaml
- name: customer_sk
  description: "{{ doc('surrogate_key') }}"
```

- `stg_customer.customer_sk` / `stg_item.item_sk` / `stg_date_dim.date_sk` の3箇所を `surrogate_key` doc blockで統一
- `stg_store_sales.customer_sk` / `item_sk` は「外部キーとしての役割」を説明する文脈が異なるため、あえて個別のdescriptionのまま残した（同じ`_sk`カラムでも役割によって説明を書き分けた例）
- `stg_store_sales_incremental` のモデル説明は長文なので doc block 化し、Markdown箇条書きがドキュメントサイト上でリスト表示されることを確認

---

## Tips: 詰まったポイント・質問した内容（ステップ6）

### 1. `dbt docs generate` が404で失敗した

**詰まった内容**: `dbt docs serve` でサイトを開くと `catalog.json` が404になり、descriptionもリネージグラフも表示されなかった。

**原因**: `dbt docs generate` 自体がコンパイルエラーで失敗していた。

```
Compilation Error in model stg_store_sales_incremental
  Required var 'max_date_sk' not found in config:
  Vars supplied to stg_store_sales_incremental = {}
```

ステップ5では `--vars '{max_date_sk: ...}'` を毎回指定して実行していたが、`dbt docs generate` はvars未指定で全モデルをコンパイルするため、`var('max_date_sk')` の参照でエラーになっていた。`target/manifest.json` は過去の実行分が残っていたため `/` や `manifest.json` は200を返す一方、`catalog.json` は今回生成されず404、という状態だった。

**修正**: `dbt_project.yml` に `vars:` でデフォルト値を設定し、`--vars` なしでも動くようにした（差分実行を試す場合は引き続き `--vars` で上書き可能）。

```yaml
vars:
  max_date_sk: 2452280  # ステップ5の段階実行で最後に使った値（2002-01-05まで取り込み済み）
```

**教訓**: `var()` を必須で使うモデルがあると、`--vars` を渡さない全体コマンド（`dbt docs generate` / `dbt run` / `dbt compile` を素で実行した場合など）が軒並み失敗する。プロジェクト全体で安全に動かすには `dbt_project.yml` にデフォルト値を用意しておくのが基本。

### 2. ドキュメントサイトのホスティング・外部カタログ連携について

localhostでの確認はできたが、社内公開や外部カタログ（Alationなど）への連携方法を調査だけ行い、実装は保留にした。

- **静的ホスティング**: `dbt docs generate` が吐く `target/`（`index.html` + `manifest.json` + `catalog.json`）はただの静的ファイルなので、GitHub Pages / S3+CloudFront / Netlify 等にそのまま置ける。dbt Cloud（有料SaaS）ならホスティングも自動。
- **`persist_docs`設定**: `description` をSnowflakeの実テーブル/ビューの `COMMENT` として書き込む機能。設定すればAlationなど**Snowflakeに直接接続するカタログツール**がdbt連携なしでコメントを拾える。
- **本格的なカタログ連携**: Alation / DataHub / Atlan などは `manifest.json` + `catalog.json` を読み込む専用のdbtコネクタを持っており、リネージとdescriptionを取り込める。

いずれも今回は実施せず、今後必要になったタイミングで着手する。

### 3. VSCodeで `ref()` の定義ジャンプが効かない

**詰まった内容**: dbt Power User拡張機能（`innoverio.vscode-dbt-power-user`）はインストール・有効化されていたが、`{{ ref(...) }}` の上で `F12` や右クリック→「定義に移動」を実行しても何も起きなかった。

**切り分けの経緯**:
1. ステータスバー自体が非表示（Zenモードなどで消えていた）→ `Ctrl+K Z` 等で復帰
2. ステータスバー復帰後、`.sql` ファイルの言語モードが **`SnowflakeSQL`** と表示されているのを確認

**原因**: 別途インストールされていたSnowflake公式拡張機能（`snowflake.snowflake-vsc`）が `.sql` 拡張子を「Snowflake SQL」言語として登録しており、dbt Power Userが機能を提供する対象の `jinja-sql` 言語モードを横取りしていた。dbt Power User自体は正常に動いていたが、対象ファイルの言語モードが合っていなかったため機能が一切アタッチされていなかった。

**修正**: ワークスペースの `.vscode/settings.json` に以下を追加し、`.sql` を強制的に `jinja-sql` として扱うようにした。

```json
{
  "files.associations": {
    "*.sql": "jinja-sql"
  }
}
```

再読み込み後、`ref()` の定義ジャンプが動作することを確認した。

**教訓**: 拡張機能が「インストール済み・有効」でも、対象ファイルの言語モードが期待通りでないと機能が発動しない。複数の拡張機能が同じ拡張子（`.sql`）を取り合う場合は、`files.associations` で明示的に決着をつける必要がある。

### 4. `{{ this }}` の役割（復習）

`{{ this }}` は実行中のモデル自身の完全修飾テーブル参照に展開される組み込みJinja変数。`stg_store_sales_incremental.sql` では以下のように使い、**ソーステーブルではなく自分自身の成果物**から差分取得の基準値（既取り込み済みの最大`sold_date_sk`）を取得している。

```sql
{% if is_incremental() %}
and ss_sold_date_sk > (select max(sold_date_sk) from {{ this }})
{% endif %}
```

`this` や `is_incremental()` などの組み込みJinjaは、プロジェクト内のマクロファイルではなくdbt-core本体のPython実装（`.venv/lib/python3.12/site-packages/dbt/context/providers.py` や `dbt/include/global_project/macros/materializations/models/incremental/is_incremental.sql`）で定義されているため、エディタの定義ジャンプでは追えない。実体を見たいときは `.venv` 配下を直接検索するとよい。

---

## ステップ6完了時点の変更ファイル

- `dbt_practice/models/staging/sources.yml`（description追加）
- `dbt_practice/models/staging/schema.yml`（description追加）
- `dbt_practice/models/intermediate/schema.yml`（新規作成）
- `dbt_practice/models/marts/schema.yml`（description追加）
- `dbt_practice/models/docs.md`（新規作成、docs block）
- `dbt_practice/dbt_project.yml`（`vars: max_date_sk` のデフォルト値追加）
- `.vscode/settings.json`（新規作成、`.sql` を `jinja-sql` に関連付け）
