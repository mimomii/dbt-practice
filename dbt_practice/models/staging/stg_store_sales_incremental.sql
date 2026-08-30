{{ config(materialized='incremental', unique_key=['ticket_number', 'item_sk'], incremental_strategy='merge') }}


with source as (
    select * from {{ source('tpcds', 'STORE_SALES') }}
    where ss_store_sk = 502
      and {{ limit_by_date_range('ss_sold_date_sk', 2452278, var('max_date_sk')) }}
      {% if is_incremental() %}
      and ss_sold_date_sk > (select max(sold_date_sk) from {{ this }})
      {% endif %}
),


renamed as (
    select
        {{ store_sales_columns() }}
    from source
)


select * from renamed
