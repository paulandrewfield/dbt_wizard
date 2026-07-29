with orders as (
    select * from {{ ref('stg_tpch_now__orders') }}
), 

lineitems as (
    select * from {{ ref('stg_tpch_now__lineitem') }}
), 

final as (
    select * from orders 
left join lineitems using (order_key)
)

select * from final


