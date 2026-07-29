select 
    order_key, 
    sum(total_price) as total_amount
from {{ ref('stg_tpch_now__orders') }}
group by 1
having sum(total_price) < 0