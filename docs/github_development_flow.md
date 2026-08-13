# GitHubでの開発フロー

チーム開発でよく使われる、Issue作成からマージまでの一連の流れをまとめる。

## 全体像

```
Issue作成 → ブランチ作成 → 作業・コミット → push → PR作成
  → CI実行 → コードレビュー → 修正 → マージ → ブランチ削除・デプロイ
```

## 各ステップの詳細

### 1. Issue作成

やるべきタスクや不具合をIssueとして起票する。

```bash
gh issue create --title "タイトル" --body "説明"
```

### 2. ブランチを切る

`main` から作業用ブランチを作成する。`main` に直接コミットしない。

```bash
git switch -c feature/add-staging-model
```

命名規則の例:

| プレフィックス | 用途 |
|------|------|
| `feature/xxx` | 新機能追加 |
| `fix/xxx` | 不具合修正 |
| `chore/xxx` | 雑務・設定変更など |

### 3. 作業してコミット

小さい単位でこまめにコミットする。

```bash
git add <ファイル>
git commit -m "分かりやすいメッセージ"
```

### 4. リモートにpush

```bash
git push -u origin feature/add-staging-model
```

### 5. Pull Request(PR)作成

`main` にマージする前にレビューを挟むための仕組み。

```bash
gh pr create --title "..." --body "..."
```

### 6. CI（自動テスト）が走る

GitHub Actionsなどで `dbt build` やlintを自動実行し、壊れていないか確認する。

### 7. コードレビュー

チームメンバーがPRにコメント・指摘 → 修正 → 再push（同じブランチに追加コミット）を繰り返す。

### 8. マージ

レビューOK・CI green後に `main` へマージする。Squash and mergeが一般的（複数コミットを1つにまとめる）。

```bash
gh pr merge --squash
```

### 9. ブランチ削除・デプロイ

マージ後は作業ブランチを削除する。CD（継続的デプロイ）が設定されていれば自動で本番反映される。

---

## このプロジェクトへの当てはめ

現状は `main` に直接commit → pushという一人開発向けのシンプルな運用。学習として「PRを使う流れ」を練習する場合は以下のように試せる。

```bash
git switch -c feature/step3
# ... 作業・コミット ...
git push -u origin feature/step3
gh pr create
gh pr merge --squash
```

一人開発でもPRを経由すると、「差分をまとめて確認する」「CIを通す」という実務の型に慣れる練習になる。
