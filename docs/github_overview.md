# GitHub 概要と重要コマンド一覧

## GitHub とは

GitHub は Git リポジトリをホスティングするウェブサービス。Git による バージョン管理に加え、以下の機能を提供する。

- **リモートリポジトリ**: コードをクラウド上で管理・共有
- **Pull Request (PR)**: コードレビューとブランチのマージ管理
- **Issues**: バグ報告・タスク管理
- **Actions**: CI/CD パイプラインの自動化

---

## Git の基本概念

| 用語 | 説明 |
|------|------|
| リポジトリ (repo) | プロジェクトのファイルと変更履歴をまとめた場所 |
| コミット (commit) | 変更のスナップショット。メッセージを付けて記録する |
| ブランチ (branch) | 独立した開発ラインを作るための分岐 |
| マージ (merge) | あるブランチの変更を別のブランチに統合する |
| クローン (clone) | リモートリポジトリをローカルにコピーする |
| プッシュ (push) | ローカルのコミットをリモートに送信する |
| プル (pull) | リモートの変更をローカルに取り込む |
| フェッチ (fetch) | リモートの変更をローカルに取得するが、作業ツリーには反映しない |
| ステージング | コミット対象のファイルを選択する（`git add`）|

---

## 重要コマンド一覧

### 初期設定

```bash
# ユーザー名とメールアドレスを設定（初回のみ）
git config --global user.name "Your Name"
git config --global user.email "you@example.com"

# 設定内容の確認
git config --list
```

### リポジトリの作成・取得

```bash
# ローカルに新規リポジトリを作成
git init

# リモートリポジトリをローカルにクローン
git clone <URL>

# GitHub CLI でリポジトリを新規作成してリモート登録まで行う
gh repo create <リポジトリ名> --public --source=. --remote=origin --push
```

### 変更の記録

```bash
# 変更状態の確認（ステージ済み・未ステージ・未追跡ファイル）
git status

# 変更差分の確認（未ステージ）
git diff

# 変更差分の確認（ステージ済み）
git diff --staged

# ファイルをステージングに追加
git add <ファイル名>

# 全変更をステージング
git add .

# コミット
git commit -m "コミットメッセージ"

# ステージングとコミットを同時に行う（新規ファイルは対象外）
git commit -am "コミットメッセージ"
```

### 履歴の確認

```bash
# コミット履歴を表示
git log

# 1行ずつ簡潔に表示
git log --oneline

# グラフ付きで表示（ブランチ確認に便利）
git log --oneline --graph --all

# 特定ファイルの変更履歴
git log -- <ファイル名>
```

### ブランチ操作

```bash
# ブランチ一覧（*が現在のブランチ）
git branch

# リモートを含む全ブランチを表示
git branch -a

# ブランチの作成
git branch <ブランチ名>

# ブランチを作成して切り替え
git checkout -b <ブランチ名>
# または（新しい書き方）
git switch -c <ブランチ名>

# ブランチの切り替え
git checkout <ブランチ名>
git switch <ブランチ名>

# ブランチを削除（マージ済みのみ）
git branch -d <ブランチ名>

# ブランチを強制削除
git branch -D <ブランチ名>
```

### リモート操作

```bash
# リモートリポジトリの確認
git remote -v

# リモートを追加
git remote add origin <URL>

# リモートの変更を取得（マージしない）
git fetch origin

# リモートの変更を取得してマージ（fetch + merge）
git pull origin <ブランチ名>

# ローカルのコミットをリモートに送信
git push origin <ブランチ名>

# 初回プッシュ（上流ブランチを設定）
git push -u origin <ブランチ名>
```

### マージとリベース

```bash
# 現在のブランチに別ブランチをマージ
git merge <ブランチ名>

# コミット履歴を直線的にまとめる（マージより履歴がきれい）
git rebase <ブランチ名>

# マージコンフリクトを解決した後
git add <解決したファイル>
git merge --continue
```

### 変更の取り消し

```bash
# ステージングを取り消す（ファイル内容は変えない）
git restore --staged <ファイル名>

# 作業ツリーの変更を取り消す（元に戻せないので注意）
git restore <ファイル名>

# 直前のコミットメッセージを修正（ローカルのみ・未プッシュのとき）
git commit --amend -m "修正後のメッセージ"

# 指定コミットを打ち消す新しいコミットを作る（履歴を書き換えない安全な方法）
git revert <コミットハッシュ>
```

### スタッシュ（一時退避）

```bash
# 作業中の変更を一時退避
git stash

# 退避した変更の一覧
git stash list

# 最新のスタッシュを取り出す
git stash pop

# 指定のスタッシュを取り出す
git stash apply stash@{n}
```

### タグ

```bash
# タグの一覧
git tag

# タグを作成
git tag <タグ名>

# 注釈付きタグを作成（リリースに使う）
git tag -a <タグ名> -m "メッセージ"

# タグをリモートにプッシュ
git push origin <タグ名>
```

---

## GitHub CLI（gh）の重要コマンド

```bash
# 認証状態の確認
gh auth status

# Pull Request の作成
gh pr create --title "タイトル" --body "説明"

# PR の一覧
gh pr list

# PR の詳細確認
gh pr view <PR番号>

# PR をブラウザで開く
gh pr view --web

# PR をマージ
gh pr merge <PR番号>

# Issue の作成
gh issue create --title "タイトル" --body "説明"

# Issue の一覧
gh issue list

# リポジトリをブラウザで開く
gh repo view --web
```

---

## よくある操作フロー

### 新機能を開発する場合

```bash
git switch -c feature/新機能名     # 作業ブランチを作成
# ... ファイルを編集 ...
git add .
git commit -m "feat: 新機能を追加"
git push -u origin feature/新機能名
gh pr create                        # Pull Request を作成
```

### リモートの最新変更を取り込む場合

```bash
git switch main
git pull origin main
git switch <作業ブランチ>
git rebase main                     # 作業ブランチに最新 main を適用
```
