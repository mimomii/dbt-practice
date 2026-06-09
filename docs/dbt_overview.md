# dbt 概要・ディレクトリ構成・作業フロー

## dbt とは

dbt（data build tool）は **Snowflakeなどのデータウェアハウス上でSQLを管理・実行するためのツール**。

従来のETLと違い、dbtは **ELT の「T（Transform）」だけ**を担う。データはすでにSnowflakeに入っている前提で、SQLで変換・整形する。

```
生データ（SNOWFLAKE_SAMPLE_DATA）
       ↓  SQL（dbtが管理）
    Staging（クリーニング）
       ↓
  Intermediate（結合・集計）
       ↓
    Marts（BIツール向け最終テーブル）
```

dbtが解決する主な問題:
- SQLをファイルで管理できる（Gitでバージョン管理）
- モデル間の依存関係を自動解決（`ref()` 関数）
- テスト・ドキュメントをコードと一緒に管理

---

## dbt_practice/ ディレクトリ構成

```
dbt_practice/
├── dbt_project.yml        ★ プロジェクトの設定ファイル（中心）
├── models/                ★ SQLファイルを置く場所（最もよく触る）
│   └── staging/           ソーステーブルのクリーニング（1:1対応）
│   └── intermediate/      結合・変換ロジック
│   └── marts/             BIツール向け最終テーブル
├── tests/                 カスタムテスト（SQLで書く）
├── macros/                再利用できるJinjaマクロ
├── seeds/                 CSVを静的テーブルとしてロード
├── snapshots/             SCD Type2（変更履歴の追跡）
├── analyses/              コンパイルだけするアドホックSQL
├── dbt_packages/          dbt deps でインストールしたパッケージ（自動生成）
├── target/                コンパイル結果・実行ログ（自動生成）
└── logs/                  実行ログ（自動生成）
```

### 主要ファイルの役割

| ファイル | 役割 |
|---|---|
| `dbt_project.yml` | プロファイル名・ディレクトリパス・デフォルトマテリアライゼーションなど |
| `models/**/*.sql` | 変換ロジック本体。`{{ config() }}` でマテリアライゼーションを指定 |
| `models/**/schema.yml` | モデルの説明・テスト（unique/not_null等）を定義するYAML |
| `~/.dbt/profiles.yml` | Snowflake接続情報（プロジェクト外に置き、絶対にGitにコミットしない） |

### `ref()` 関数

モデル間の依存関係を記述するための関数。dbtが実行順序を自動解決する。

```sql
-- my_second_dbt_model.sql
select * from {{ ref('my_first_dbt_model') }}
```

---

## マテリアライゼーション

| 種別 | 説明 |
|---|---|
| `view`（デフォルト） | Snowflakeにビューとして作成。毎回クエリ実行 |
| `table` | テーブルとして作成。毎回全件再構築 |
| `incremental` | 差分のみ追加。大テーブルに有効 |
| `ephemeral` | CTEとして展開。Snowflakeに実体を作らない |

```sql
-- モデルファイル内で上書き可能
{{ config(materialized='table') }}
```

---

## 基本的な作業フロー

```
① models/ にSQLファイルを追加・編集
        ↓
② dbt compile    構文チェック（Snowflakeに接続しない）
        ↓
③ dbt run        Snowflakeでモデルを実行（テーブル/ビューを作成）
        ↓
④ dbt test       schema.yml のテストを実行（unique/not_null など）
        ↓
⑤ dbt docs generate && dbt docs serve    ドキュメントをブラウザで確認
```

> `dbt build` = `dbt run` + `dbt test` を一括実行するショートカット

### よく使うオプション

```bash
dbt run --select <モデル名>       # 特定モデルだけ実行
dbt run --select +<モデル名>      # 上流の依存モデルも含めて実行
dbt test --select <モデル名>      # 特定モデルのテストだけ実行
dbt ls --select +<モデル名>+      # 依存グラフの確認
```

---

## コスト管理（Snowflake従量課金のため厳守）

- ウェアハウスは **X-Small** を使用
- auto-suspend: **60秒**、auto-resume: **有効**
- 練習データは `SNOWFLAKE_SAMPLE_DATA` を使い、自前ロードは避ける
