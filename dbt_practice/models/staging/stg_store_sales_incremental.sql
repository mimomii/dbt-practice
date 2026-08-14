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
