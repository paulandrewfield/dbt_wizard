-- ====================================================
-- proc: build_fct_orders_by_status (finance mart)
-- owner: rwilson@ / reviewed m.tan
-- created 2023-02-14, last touched 2023-04-28
-- ticket FIN-2271 - "orders summarized by status for AR aging tab"
-- TODO: dedupe this, mostly copied from fct_order_items_monthly rollup pattern
-- TODO: (2023-09) the above TODO is now 7 months old, it is three rows, leave it
-- pg port: plain group-by rollup, no snowflake-isms.
-- ====================================================
create or replace procedure retail_datamart.build_fct_orders_by_status() language plpgsql set search_path = retail_datamart, public as $$ begin
drop table if exists retail_datamart.fct_orders_by_status;
create table retail_datamart.fct_orders_by_status (status_code varchar, order_count numeric(38,0), return_count numeric(38,0), gross_item_sales_amount decimal(16,3), net_item_sales_amount decimal(16,3), item_tax_amount decimal(16,3));
-- one row per status_code. finance wants gross AND net, do not collapse.
insert into retail_datamart.fct_orders_by_status (status_code, order_count, return_count, gross_item_sales_amount, net_item_sales_amount, item_tax_amount) select status_code, sum(order_count), sum(return_count), sum(gross_item_sales_amount), sum(net_item_sales_amount), sum(item_tax_amount) from fct_orders group by 1 order by 1;
raise notice 'fct_orders_by_status built';
end $$;
