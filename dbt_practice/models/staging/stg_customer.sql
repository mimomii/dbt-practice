with source as (
    select * from {{ source('tpcds', 'CUSTOMER')}} 
),
renamed as (
    select
        c_customer_sk   as customer_sk,
        c_customer_id   as customer_id,
        c_first_name    as first_name,
        c_last_name     as last_name,
        c_email_address as email_address
    from source
)
select * from renamed