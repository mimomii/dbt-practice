select *
from {{ ref('stg_store_sales') }}
where quantity < 0