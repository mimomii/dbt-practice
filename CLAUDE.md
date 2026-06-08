# CLAUDE.md

このファイルは、Claude Code (claude.ai/code) がこのリポジトリで作業する際のガイダンスを提供します。

## 環境

Pythonの仮想環境は `.venv/` にあります。dbtコマンドを実行する前に必ず有効化してください:

```bash
source .venv/bin/activate
```

インストール済みアダプタ: **dbt-snowflake 1.11.5**（dbt-core 1.11.11）

## よく使うコマンド

```bash
# 新規dbtプロジェクトの初期化
dbt init <プロジェクト名>

# packages.ymlに記載した依存パッケージのインストール
dbt deps

# モデルのコンパイル（実行なし・SQLの検証のみ）
dbt compile

# 全モデルの実行
dbt run

# 特定モデルの実行
dbt run --select <モデル名>

# 上流の依存モデルも含めて実行
dbt run --select +<モデル名>

# テストの実行
dbt test

# 特定モデルのテスト実行
dbt test --select <モデル名>

# 実行とテストをまとめて行う
dbt build

# ドキュメントの生成とサーブ
dbt docs generate
dbt docs serve

# リネージ・依存グラフの表示
dbt ls --select +<モデル名>+
```

## dbtプロジェクト構造（初期化後）

```
<プロジェクト名>/
├── dbt_project.yml       # プロジェクト設定（名前・バージョン・モデルパス・マテリアライゼーション）
├── profiles.yml          # 接続設定（通常は ~/.dbt/profiles.yml に配置）
├── packages.yml          # パッケージ依存（dbt-utils など）
├── models/
│   ├── staging/          # ソース生データのクリーニング（ソーステーブルと1:1対応）
│   ├── intermediate/     # ビジネスロジックの結合・変換
│   └── marts/            # BIツールに公開する最終テーブル
├── tests/                # カスタム単体テスト（.sqlファイル）
├── macros/               # 再利用可能なJinjaマクロ
├── seeds/                # `dbt seed` で読み込む静的CSVデータ
├── snapshots/            # `dbt snapshot` によるSCD Type 2履歴追跡
└── analyses/             # アドホックSQL（コンパイルのみ、実行なし）
```

## Snowflake接続

Snowflakeの接続設定は `~/.dbt/profiles.yml` に記載します。プロファイル名は `dbt_project.yml` の `profile:` と一致させてください。主要フィールド:

```yaml
<プロファイル名>:
  target: dev
  outputs:
    dev:
      type: snowflake
      account: <アカウント識別子>
      user: <ユーザー名>
      password: <パスワード>          # または authenticator: externalbrowser
      role: <ロール>
      warehouse: <ウェアハウス>
      database: <データベース>
      schema: <スキーマ>
```

接続確認は `dbt debug` で行います。

## マテリアライゼーション

デフォルトのマテリアライゼーションは `view` です。`dbt_project.yml` またはモデルのconfigブロックで上書きできます:

```sql
{{ config(materialized='table') }}   -- 'incremental' や 'ephemeral' も可
```

インクリメンタルモデルにはユニークキーと `is_incremental()` フィルタが必要です:

```sql
{{ config(materialized='incremental', unique_key='id') }}
select ...
{% if is_incremental() %}
  where updated_at > (select max(updated_at) from {{ this }})
{% endif %}
```

# dbt練習プロジェクト 引き継ぎメモ

## 目的

SnowflakeのデータをdbtでELT変換する練習。学習用の環境。

## 現在の状態

- OS: WSL上のUbuntu
- 作業ディレクトリ: ~/dbt-practice（Linux側ホーム配下）
- Python仮想環境: ~/dbt-practice/.venv（都度 `source .venv/bin/activate` で有効化）
- dbt-snowflake / dbt-core: インストール済み（`dbt --version` で確認可）
- GitHub: gh CLIで認証済み（アカウント mimomii、トークンに repo スコープあり）
- git: このプロジェクトはまだ `git init` していない

## これからやること（未着手）

1. `dbt init` でプロジェクト雛形を生成（Snowflakeアダプタを選択）
2. profiles.yml をSnowflake接続用に設定（後述の制約を厳守）
3. .gitignore に `.venv/`、`target/`、`dbt_packages/`、`logs/` を含める
4. `git init` → `gh repo create` で新規リポジトリ作成 → 初回push（mainブランチ）
5. このCLAUDE.mdをmainに配置

## 重要な制約（コスト・セキュリティ）

- profiles.yml にSnowflakeの認証情報を含めるため、絶対にGitHubへコミットしない。
  ~/.dbt/profiles.yml（プロジェクト外）に置くのが基本。
- Snowflakeは無料クレジット消費済みで従量課金中。コストを最小化すること:
  - ウェアハウスは必ず X-Small
  - auto-suspend は 60秒、auto-resume は有効
- 練習データはSnowflake組み込みの SNOWFLAKE_SAMPLE_DATA を使い、自前ロードは避ける
