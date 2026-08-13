select
    year,
    month_of_year,
    sum(total_net_paid) as total_net_paid,
    sum(total_quantity) as total_quantity,
    sum(order_count) as order_count
from {{ ref('int_daily_sales') }}
group by year, month_of_year