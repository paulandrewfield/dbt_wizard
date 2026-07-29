    select
O_ORDERKEY as order_key, 
O_ORDERDATE as order_date, 
O_ORDERTIME as order_time, 
O_CUSTKEY as customer_key, 
O_ORDERSTATUS as order_status, 
O_TOTALPRICE as total_price, 
O_ORDERPRIORITY as order_priority, 
O_CLERK as order_clerk, 
O_SHIPPRIORITY as order_ship_priority, 
O_COMMENT as order_comment

    from {{ source('tpch_now', 'orders') }}