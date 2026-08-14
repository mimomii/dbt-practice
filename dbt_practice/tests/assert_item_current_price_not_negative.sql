select *
from {{ ref('stg_item') }}
where current_price < 0