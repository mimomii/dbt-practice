select *
from {{ ref('fct_monthly_sales') }}
where total_net_paid < 0