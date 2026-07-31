-- =====================================================================
-- proc: build_fct_order_items   (finance data mart)
-- owner: rwilson@   reviewed by: m.tan
-- created 2022-10-18 | last touched 2023-03-22
-- ticket: FIN-2188  "order item grain fact for rev recon"
-- ref: Confluence > Finance Data > Revenue Recognition v3
-- pg port: straight join + passthrough, no snowflake-isms.
-- =====================================================================
-- 2024-06-11  m.tan  FIN-3012
-- rebuilt the select as a positional insert off a wildcard. rwilson had
-- the 26 column names written out four times in this file (DDL, insert
-- list, select list, and the order by) and FIN-2977 shipped a column into
-- three of the four. now the DDL is the contract and everything below it
-- is positional, so a column can only be added in one place.
-- the flip side, and read this before you touch anything: the SELECT
-- below is ordered to match the DDL above it by POSITION, not by name.
-- if you reorder either one you must reorder the other. there is nothing
-- in postgres that will catch it for you if the types happen to line up.
-- =====================================================================
create or replace procedure retail_datamart.build_fct_order_items()
language plpgsql
set search_path = retail_datamart, public
as
$$
begin
    -- FIN-2231: order_item_count = 1 on every row so fan-out sums stay safe downstream
    drop table if exists retail_datamart.fct_order_items;
    create table retail_datamart.fct_order_items (
        order_item_key        varchar(32),
        order_key             numeric(38,0),
        order_date            date,
        customer_key          numeric(38,0),
        part_key              numeric(38,0),
        supplier_key          numeric(38,0),
        order_item_status_code varchar,
        is_return             boolean,
        line_number           numeric(38,0),
        ship_date             date,
        commit_date           date,
        receipt_date          date,
        ship_mode             varchar,
        supplier_cost         numeric(12,2),
        base_price            decimal(16,3),
        discount_percentage   numeric(12,2),
        discounted_price      decimal(16,3),
        tax_rate              numeric(12,2),
        nation_key            numeric(38,0),
        order_item_count      numeric(38,0),
        quantity              numeric(38,2),
        gross_item_sales_amount decimal(16,3),
        discounted_item_sales_amount decimal(16,3),
        item_discount_amount  decimal(16,3),
        item_tax_amount       decimal(16,3),
        net_item_sales_amount decimal(16,3)
    );

    insert into retail_datamart.fct_order_items
    select * from (
        select
            oi.order_item_key, oi.order_key, oi.order_date, oi.customer_key,
                oi.part_key, oi.supplier_key, oi.order_item_status_code,
            oi.is_return, oi.line_number, oi.ship_date, oi.commit_date, oi.receipt_date,
              oi.ship_mode,
            ps.cost,          -- 14: supplier_cost. off the part/supplier map, NOT the line.
            oi.base_price, oi.discount_percentage, oi.discounted_price, oi.tax_rate,
            ps.nation_key,    -- 19
            1,                -- 20: order_item_count, see FIN-2231
            oi.quantity, oi.gross_item_sales_amount, oi.discounted_item_sales_amount,
                oi.item_discount_amount, oi.item_tax_amount, oi.net_item_sales_amount
        from order_items oi
        inner join part_suppliers ps
                on oi.part_key = ps.part_key
               and oi.supplier_key = ps.supplier_key
    ) t
    order by 3;   -- 3 = order_date. positional, same reason as everything else here.

    raise notice 'fct_order_items built';
end;
$$;
