select
    customer_id,
    first_name,
    last_name,
    sum(net_paid) as total_net_paid,
    sum(quantity) as total_quantity,
    count(distinct ticket_number) as order_count 
from {{ ref('int_sales_with_customer') }}
group by
    customer_id,
    first_name,
    last_name