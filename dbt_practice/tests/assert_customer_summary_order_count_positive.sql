select *
from {{ ref('fct_customer_summary') }}
where order_count < 1