with source as (
    select * from {{ source('tpcds', 'STORE_SALES') }}
    where ss_sold_date_sk in (
        select d_date_sk
        from {{ source('tpcds', 'DATE_DIM') }}
        where d_year = 2002
    )
),

renamed as (
    select
        ss_sold_date_sk as sold_date_sk,
        ss_item_sk      as item_sk,
        ss_customer_sk  as customer_sk,
        ss_ticket_number as ticket_number,
        ss_quantity     as quantity,
        ss_sales_price  as sales_price,
        ss_net_paid     as net_paid
    from source
)

select * from renamed
