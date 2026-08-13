select
    ss.sold_date_sk,
    ss.ticket_number,
    ss.quantity,
    ss.sales_price,
    ss.net_paid,
    c.customer_id,
    c.first_name,
    c.last_name,
    i.item_desc,
    i.category,
    i.brand
from {{ ref('stg_store_sales') }} ss
left join {{ ref('stg_customer') }} c
    on ss.customer_sk = c.customer_sk
left join {{ ref('stg_item') }} i
    on ss.item_sk = i.item_sk