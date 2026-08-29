with source as (
    select * from {{ source('tpcds', 'STORE_SALES') }}
    where {{ limit_by_date_range('ss_sold_date_sk', 2452278, 2452278) }}
),


renamed as (
    select
        {{ store_sales_columns() }}
    from source
)


select * from renamed
