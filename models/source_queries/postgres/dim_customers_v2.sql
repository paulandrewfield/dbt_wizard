/*
build_dim_customers_v2                                    sam.okafor 2022-09-01
--------------------------------------------------------------------------------
the customer_flags variant. same upstream joins as v1, different payload:
high/mid/low value flags instead of tier_name.

DO NOT consolidate v1 and v2 "because they look similar". they have different
consumers and the two get certified separately.

2023-08-14 / v.krishnan
un-CTE'd it. i needed the region join to materialise before the flags join
for the DA-871 investigation and nesting was the fastest way to force the
shape without adding hints. the shape is load bearing now, three of the
reconciliation queries assume this row order. do not flatten it back out.
(v1 got flattened. v1 is not certified. that is the difference.)

pg port: snowflake "create or replace table .. as" -> drop + create as.
*/
create or replace procedure retail_datamart.build_dim_customers_v2()
language plpgsql
set search_path = retail_datamart, public
as
$$
begin
    drop table if exists retail_datamart.dim_customers_v2;

    create table retail_datamart.dim_customers_v2 as
    select *
      from (
        select x2.customer_key
             , x2.name
             , x2.name_prefix
             , x2.name_id
             , x2.address
             , x2.nation
             , x2.region
             , x2.phone_number
             , x2.account_balance
             , x2.market_segment
             , x3.lifetime_value
             , x3.is_high_value
             , x3.is_mid_value
             , x3.is_low_value
          from (
                select x1.customer_key
                     , x1.name
                     , x1.name_prefix
                     , x1.name_id
                     , x1.address
                     , x1.phone_number
                     , x1.account_balance
                     , x1.market_segment
                     , x1.nation
                     , rg.name as region
                  from (
                        select c.customer_key
                             , c.name
                             , c.name_prefix
                             , c.name_id
                             , c.address
                             , c.phone_number
                             , c.account_balance
                             , c.market_segment
                             , n.name       as nation
                             , n.region_key as region_key
                          from stg_tpch_customers c
                               inner join stg_tpch_nations n
                                       on c.nation_key = n.nation_key
                       ) x1
                       inner join stg_tpch_regions rg
                               on rg.region_key = x1.region_key
               ) x2
               -- LEFT. unscored customers stay in. same as v1.
               left join customer_flags x3
                      on x3.customer_key = x2.customer_key
      ) x4
     order by customer_key;

    raise notice 'dim_customers_v2 built';
end;
$$;
