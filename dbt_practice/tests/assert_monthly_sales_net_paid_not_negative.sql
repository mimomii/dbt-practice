select *
from {{ ref('mart_monthly_sales') }}
where total_net_paid < 0