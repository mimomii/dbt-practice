{#
    stg_store_sales と stg_store_sales_incremental で重複していた
    STORE_SALES のカラムリネーム定義を共通化したもの。
    呼び出し側の renamed CTE の select に展開して使う。
#}
{% macro store_sales_columns() -%}
    ss_sold_date_sk  as sold_date_sk,
    ss_item_sk       as item_sk,
    ss_customer_sk   as customer_sk,
    ss_ticket_number as ticket_number,
    ss_quantity      as quantity,
    ss_sales_price   as sales_price,
    ss_net_paid      as net_paid
{%- endmacro %}
