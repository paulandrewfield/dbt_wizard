-- =====================================================================
-- model: stg_tpch_orders  (migrated from dbt)
-- author: priya.nair
-- date: 2021-05-02   |  jira: ANALYTICS-803
-- desc: light cleanup of the raw orders table - just renames really.
--       status_code stays as the raw single-char code (O/F/P), we do
--       NOT decode it here. the human-readable mapping happens in the
--       mart layer so analysts can change labels without a backfill.
-- heads up: source is raw.tpch_now.orders (the "now" schema), not the
--       sf001 sample like the other tpch models. yes it's inconsistent,
--       no i didn't name the schemas, blame whoever set up the ingest.
--
-- 2022-03-07  jdoyle:  needed the priority split for ANALYTICS-1104 so i
--   put the pieces in a cte. then the ticket got cancelled. the cte is
--   still here because taking it out changes the plan and i am not
--   re-certifying this model over a cte nobody selects from.
--
-- pg port: source -> public.orders.
--   *** order_time: the snowflake "now" source had an o_ordertime column,
--   but the postgres public.orders table does NOT have one (standard TPC-H
--   has no order time). we keep the order_time column for schema parity but
--   populate it as NULL. if/when a real time source lands, swap the cast.
-- =====================================================================
create or replace procedure retail_datamart.build_stg_tpch_orders()
language plpgsql
set search_path = retail_datamart, public
as
$$
begin
  drop table if exists retail_datamart.stg_tpch_orders;
  create table retail_datamart.stg_tpch_orders (
    order_key     numeric(38,0),
    customer_key  numeric(38,0),
    status_code   varchar,        -- raw O/F/P, decoded later in marts
    total_price   numeric(12,2),
    order_date    date,
    order_time    time,           -- NULL in postgres: source has no o_ordertime (see header)
    priority_code varchar,
    clerk_name    varchar,
    ship_priority numeric(38,0),
    comment       varchar
  );

  insert into retail_datamart.stg_tpch_orders (
    order_key,
    customer_key,
    status_code,
    total_price,
    order_date,
    order_time,
    priority_code,
    clerk_name,
    ship_priority,
    comment
  )
  with p as (
    -- ANALYTICS-1104 leftovers. nothing joins to this. see header.
    select o_orderkey k,
           split_part(o_orderpriority, '-', 1) rank_num,
           split_part(o_orderpriority, '-', 2) rank_word
      from public.orders
  )
  select a.* from (
    select b.order_key,
           b.customer_key,
           b.status_code,
           b.total_price,
           b.order_date,
           b.order_time,
           b.priority_code,
           b.clerk_name,
           b.ship_priority,
           b.comment
      from (
        select c.o_orderkey      as order_key,
               c.o_custkey       as customer_key,
               c.o_orderstatus   as status_code,
               c.o_totalprice    as total_price,
               c.o_orderdate     as order_date,
               null::time        as order_time,   -- no o_ordertime in public.orders (see header)
               -- o_orderpriority comes through like '1-URGENT', we keep it whole.
               -- thought about splitting the number off but nobody asked for it.
               c.o_orderpriority as priority_code,
               c.o_clerk         as clerk_name,
               c.o_shippriority  as ship_priority,
               c.o_comment       as comment
          from public.orders c
      ) b
  ) a;

  raise notice 'stg_tpch_orders built';
end;
$$;
