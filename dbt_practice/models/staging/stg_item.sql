with source as (
    select * from {{ source('tpcds', 'ITEM') }}
),

renamed as (
    select
        i_item_sk       as item_sk,
        i_item_id       as item_id,
        i_item_desc     as item_desc,
        i_current_price as current_price,
        i_category      as category,
        i_brand         as brand
    from source
)

select * from renamed
