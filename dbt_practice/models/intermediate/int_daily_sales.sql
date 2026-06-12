select
    dd.date_day,
    dd.year,
    dd.month_of_year,
    sum(ss.net_paid) as total_net_paid,
    sum(ss.quantity) as total_quantity,
    count(*) as order_count
from {{ ref('stg_store_sales') }} ss
left join {{ ref('stg_date_dim') }} dd
    on ss.sold_date_sk = dd.date_sk
group by dd.date_day, dd.year, dd.month_of_year