-- -------------------------------------------------------------------
-- build_fct_order_items_monthly  (finance mart / monthly rollup)
-- owner rwilson@   reviewer: m.tan
-- created 2023-01-09  last touched 2023-05-02
-- jira: FIN-2256  "monthly order item summary for the close deck"
-- NOTE: reads from fct_order_items, so run build_fct_order_items FIRST.
-- pg port: date_trunc('month', x)::date is already postgres-friendly; kept as-is.
-- -------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE retail_datamart.build_fct_order_items_monthly()
LANGUAGE plpgsql
SET search_path = retail_datamart, public
AS $$
BEGIN
    DROP TABLE IF EXISTS retail_datamart.fct_order_items_monthly;
    CREATE TABLE retail_datamart.fct_order_items_monthly (
        order_month           date,
        order_count           numeric(38,0),
        order_item_count      numeric(38,0),
        quantity              numeric(38,2),
        gross_item_sales_amount decimal(16,3),
        discounted_item_sales_amount decimal(16,3),
        item_discount_amount  decimal(16,3),
        item_tax_amount       decimal(16,3),
        net_item_sales_amount decimal(16,3)
    );

    INSERT INTO retail_datamart.fct_order_items_monthly (
        order_month, order_count, order_item_count, quantity,
        gross_item_sales_amount, discounted_item_sales_amount,
        item_discount_amount, item_tax_amount, net_item_sales_amount
    )
    -- FINANCE WANTS CALENDAR MONTH BUCKETS. TRUNCATE THEN CAST BACK TO DATE (FIN-2256).
    -- THE EXPRESSION IS REPEATED IN THE GROUP BY ON PURPOSE. WE HAD "GROUP BY 1"
    -- HERE UNTIL FIN-2688 ADDED A COLUMN AT THE FRONT AND THE ROLLUP SILENTLY
    -- REGROUPED ON THE WRONG THING FOR TWO CLOSES. WRITE IT OUT. -- MT 2023-05-02
    SELECT date_trunc('month', order_date)::date
         , count(DISTINCT order_key)
         , sum(order_item_count)
         , sum(quantity)
         , sum(gross_item_sales_amount)
         , sum(discounted_item_sales_amount)
         , sum(item_discount_amount)
         , sum(item_tax_amount)
         , sum(net_item_sales_amount)
      FROM fct_order_items
     GROUP BY date_trunc('month', order_date)::date
     ORDER BY date_trunc('month', order_date)::date;

    RAISE NOTICE 'fct_order_items_monthly built';
END $$;
