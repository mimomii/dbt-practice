select
    customer_id,
    first_name,
    last_name,
    {{ round_money('sum(net_paid)') }} as total_net_paid,
    sum(quantity) as total_quantity,
    count(distinct ticket_number) as order_count 
from {{ ref('int_store_sales_enriched') }}
where customer_id is not null
group by
    customer_id,
    first_name,
    last_name