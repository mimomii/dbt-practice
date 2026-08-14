select *
from {{ ref('stg_store_sales') }}
where sales_price < 0