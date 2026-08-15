{% docs surrogate_key %}
ソーステーブルの主キーを内部的に採番した代理キー（サロゲートキー）。
自然キー（`customer_id`など）と異なり業務的な意味を持たず、モデル間のJOINキーとしてのみ使用する。
{% enddocs %}

{% docs stg_store_sales_incremental %}
店舗ID 502の売上明細を対象としたincrementalモデル。

- 初回実行時: `sold_date_sk` が `2452278`〜`var('max_date_sk')` の範囲を取り込む
- 2回目以降: `is_incremental()` が真になり、取り込み済みの最大`sold_date_sk`より新しいレコードのみを差分取得する
- `unique_key` に `['ticket_number', 'item_sk']` を指定しているため、同一キーの行は`MERGE`で上書きされ重複しない

検証の詳細は `docs/step5_学習まとめ.md` を参照。
{% enddocs %}
