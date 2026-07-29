CREATE OR REPLACE PROCEDURE sp_transform_warehouse_layers()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
BEGIN
    ---------------------------------------------------------
    -- 1. POPULATE / UPDATE CUSTOMER DIMENSION
    ---------------------------------------------------------
    MERGE INTO DIM_CUSTOMERS tgt
    USING STG_CUSTOMER src
    ON tgt.customer_key = src.c_custkey
    WHEN MATCHED THEN UPDATE SET
        tgt.customer_name = src.c_name,
        tgt.market_segment = src.c_mktsegment,
        tgt.acct_balance = src.c_acctbal,
        tgt.phone_number = src.c_phone,
        tgt.dw_load_timestamp = CURRENT_TIMESTAMP()
    WHEN NOT MATCHED THEN INSERT (customer_key, customer_name, market_segment, acct_balance, phone_number)
    VALUES (src.c_custkey, src.c_name, src.c_mktsegment, src.c_acctbal, src.c_phone);

    ---------------------------------------------------------
    -- 2. POPULATE / UPDATE FACT ORDER ITEMS
    ---------------------------------------------------------
    MERGE INTO FACT_ORDER_ITEMS tgt
    USING (
        SELECT 
            -- Build a clean, deterministically unique ID for the fact row
            CONCAT(l.l_orderkey, '-', l.l_linenumber) AS order_item_id,
            l.l_orderkey AS order_key,
            o.o_custkey AS customer_key,
            l.l_partkey AS part_key,
            l.l_suppkey AS supplier_key,
            l.l_linenumber AS line_number,
            o.o_orderdate AS order_date,
            l.l_quantity AS quantity,
            l.l_extendedprice AS extended_price,
            l.l_discount AS discount,
            l.l_tax AS tax,
            -- Derived dynamic metrics
            (l.l_extendedprice * (1 - l.l_discount))::NUMBER(12,2) AS net_revenue,
            (ps.ps_supplycost * l.l_quantity)::NUMBER(12,2) AS supply_cost
        FROM STG_LINEITEM l
        JOIN STG_ORDERS o ON l.l_orderkey = o.o_orderkey
        JOIN STG_PARTSUPP ps ON l.l_partkey = ps.ps_partkey AND l.l_suppkey = ps.ps_suppkey
        JOIN STG_PART p ON l.l_partkey = p.p_partkey
        JOIN STG_SUPPLIER s ON l.l_suppkey = s.s_suppkey
    ) src
    ON tgt.order_item_id = src.order_item_id
    WHEN MATCHED THEN UPDATE SET
        tgt.quantity = src.quantity,
        tgt.extended_price = src.extended_price,
        tgt.discount = src.discount,
        tgt.tax = src.tax,
        tgt.net_revenue = src.net_revenue,
        tgt.supply_cost = src.supply_cost,
        tgt.dw_load_timestamp = CURRENT_TIMESTAMP()
    WHEN NOT MATCHED THEN INSERT (
        order_item_id, order_key, customer_key, part_key, supplier_key, 
        line_number, order_date, quantity, extended_price, discount, 
        tax, net_revenue, supply_cost
    )
    VALUES (
        src.order_item_id, src.order_key, src.customer_key, src.part_key, src.supplier_key, 
        src.line_number, src.order_date, src.quantity, src.extended_price, src.discount, 
        src.tax, src.net_revenue, src.supply_cost
    );

    RETURN 'SUCCESS: Dimensional Warehouse tables fully populated.';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'FAILED: ' || SQLERRM;
END;
$$;