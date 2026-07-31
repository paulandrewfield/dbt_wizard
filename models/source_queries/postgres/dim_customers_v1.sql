------------------------------------------------------------------------
-- build_dim_customers_v1
-- @sam.okafor  2022-09-01
-- v1 is deprecated but reporting still queries it, so it lives.
-- if you "clean this up" and break the morning dashboards, that's on you.
--
-- @sam.okafor 2024-01-22
-- it is still here. it is still deprecated. it has now outlived two of the
-- dashboards it was kept alive for. i have stopped writing the migration
-- note at the top of this file, there have been four of them.
--
-- pg port: snowflake "create or replace table .. as" -> drop + create as.
------------------------------------------------------------------------
create or replace procedure retail_datamart.build_dim_customers_v1()
language plpgsql
set search_path = retail_datamart, public
as
$$
begin
    -- CTAS instead of DDL + INSERT. typing the column list twice is a waste,
    -- and the types here are already nailed down upstream in staging.
    --
    -- the CTE stack this used to have (customers / nations / regions /
    -- tiers / final, five of them, each one a bare select from one table)
    -- is folded down to the join it always compiled to. v2 still has the
    -- long form if you want to diff them.
    drop table if exists retail_datamart.dim_customers_v1;
    create table retail_datamart.dim_customers_v1 as
    select
        c.customer_key
      , c.name
      , c.name_prefix
      , c.name_id
      , c.address
      , n.name as nation
      , r.name as region
      , c.phone_number
      , c.account_balance
      , c.market_segment
      , t.lifetime_value
      , t.tier_name
    from      stg_tpch_customers c
    join      stg_tpch_nations   n on n.nation_key = c.nation_key
    join      stg_tpch_regions   r on r.region_key = n.region_key
    left join customer_tier      t on t.customer_key = c.customer_key
      -- ^ LEFT. not every customer has been scored yet and dropping the
      --   unscored ones changes the row count reporting reconciles to.
    order by c.customer_key;

    raise notice 'dim_customers_v1 built';
end;
$$;
