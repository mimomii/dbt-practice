with source as (
    select * from {{ source('tpcds', 'DATE_DIM') }}
),

renamed as (
    select
        d_date_sk   as date_sk,
        d_date      as date_day,
        d_year      as year,
        d_moy       as month_of_year,
        d_dom       as day_of_month
    from source
)

select * from renamed
