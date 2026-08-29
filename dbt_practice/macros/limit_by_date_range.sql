
{#
    コスト対策として date_sk カラムを指定範囲に絞り込むwhere句断片。
    STORE_SALESのような巨大テーブルのフルスキャンを防ぐために
    stg_store_sales系のモデルで使う。
    start_date_sk と end_date_sk に同じ値を渡せば単日絞り込みにもなる。
#}
{% macro limit_by_date_range(date_column, start_date_sk, end_date_sk) -%}
    {{ date_column }} between {{ start_date_sk }} and {{ end_date_sk }}
{%- endmacro %}

