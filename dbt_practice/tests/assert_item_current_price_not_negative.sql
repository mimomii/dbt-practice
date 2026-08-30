select *
from {{ ref('stg_items') }}
where current_price < 0