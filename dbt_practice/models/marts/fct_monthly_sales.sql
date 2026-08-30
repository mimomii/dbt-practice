select
    year,
    month_of_year,
    {{ round_money('sum(total_net_paid)') }} as total_net_paid,
    sum(total_quantity) as total_quantity,
    sum(order_count) as order_count
from {{ ref('int_store_sales_aggregated_to_day') }}
group by year, month_of_year