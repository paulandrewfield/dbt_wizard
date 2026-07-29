select
    fct_order_item_key,
    sum(LINE_QUANTITY_ORDERED) as total_amount
from {{ ref('fct_order_items_local' )}}
group by 1
having not(total_amount >= 0)