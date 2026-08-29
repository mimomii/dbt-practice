{#
    金額カラムの表示桁数を揃えるための共通マクロ。
    decimal_places のデフォルトは2桁（通貨の一般的な精度）。
#}
{% macro round_money(column_name, decimal_places=2) -%}
    round({{ column_name }}, {{ decimal_places }})
{%- endmacro %}
