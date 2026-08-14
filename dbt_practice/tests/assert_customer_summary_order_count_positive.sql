select *
from {{ ref('mart_customer_summary') }}
where order_count < 1