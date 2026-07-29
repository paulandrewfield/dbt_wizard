    select
L_ORDERKEY as order_key, 
L_SHIPDATE as ship_date, 
L_COMMITDATE as commit_date, 
L_RECEIPTDATE as receipt_date, 
L_PARTKEY as part_key, 
L_SUPPKEY as supplier_key, 
L_LINENUMBER as line_number, 
L_QUANTITY as line_quantity_ordered, 
L_EXTENDEDPRICE as line_extended_price, 
L_DISCOUNT as line_discount, 
L_TAX as line_tax, 
L_RETURNFLAG as line_return_flag, 
L_LINESTATUS as line_status, 
L_SHIPINSTRUCT as line_ship_instruct, 
L_SHIPMODE as line_ship_mode, 
L_COMMENT as line_comment

    from {{ source('tpch_now', 'lineitem') }}