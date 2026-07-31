-- ###################################################################
-- proc: build_fct_orders  (finance mart)
-- owner: rwilson@  | reviewed: m.tan
-- created 2022-11-30, last touched 2023-04-15
-- ticket: FIN-2207  "orders fact for revenue dashboard"
-- per finance request: keep gross/net split, DO NOT collapse to a single amount
-- pg port: snowflake count_if(cond) -> count(*) filter (where cond).
--          order_time carries through as NULL (see stg_tpch_orders header).
-- ###################################################################
create or replace procedure retail_datamart.build_fct_orders()
language plpgsql
set search_path = retail_datamart, public
as
$$
declare
    n_orders  bigint;
    n_out     bigint;
begin
    drop table if exists retail_datamart.fct_orders;
    create table retail_datamart.fct_orders (
        order_key             numeric(38,0),
        order_date            date,
        order_time            time,
        customer_key          numeric(38,0),
        status_code           varchar,
        priority_code         varchar,
        clerk_name            varchar,
        ship_priority         numeric(38,0),
        order_count           numeric(38,0),
        return_count          numeric(38,0),
        gross_item_sales_amount decimal(16,3),
        item_discount_amount  decimal(16,3),
        item_tax_amount       decimal(16,3),
        net_item_sales_amount decimal(16,3)
    );

    insert into retail_datamart.fct_orders (
        order_key, order_date, order_time, customer_key, status_code,
        priority_code, clerk_name, ship_priority, order_count, return_count,
        gross_item_sales_amount, item_discount_amount, item_tax_amount,
        net_item_sales_amount
    )
    select q2.order_key
         , q2.order_date
         , q2.order_time
         , q2.customer_key
         , q2.status_code
         , q2.priority_code
         , q2.clerk_name
         , q2.ship_priority
         , 1                       -- order grain. 1 per row. same pattern as fct_order_items.order_item_count.
         , q2.rc
         , q2.g
         , q2.d
         , q2.x
         , q2.n
      from (
        select o.order_key, o.order_date, o.order_time, o.customer_key,
               o.status_code, o.priority_code, o.clerk_name, o.ship_priority,
               q1.rc, q1.g, q1.d, q1.x, q1.n
          from stg_tpch_orders o
             , (
                select order_key ok
                     , sum(gross_item_sales_amount) g
                     , sum(item_discount_amount)    d
                     , sum(item_tax_amount)         x
                     , sum(net_item_sales_amount)   n
                     -- count_if(is_return = true) in snowflake. FILTER is the
                     -- postgres spelling, there is no count_if. FIN-2207.
                     , count(*) filter (where is_return = true) rc
                  from order_items
                 group by order_key
               ) q1
         where o.order_key = q1.ok
      ) q2
     order by q2.order_date;

    get diagnostics n_out = row_count;
    select count(*) into n_orders from retail_datamart.stg_tpch_orders;

    -- inner join above. orders with no line items are supposed to fall out.
    -- if this ever gets loud, check whether line items went missing rather
    -- than assuming the join is wrong.
    if n_out <> n_orders then
        raise notice 'fct_orders: % of % orders had line items', n_out, n_orders;
    end if;

    raise notice 'fct_orders built';
end;
$$;
