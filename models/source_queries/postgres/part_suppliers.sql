-----------------------------------------------------------------------
-- part_suppliers
-- dmitri k 2021/01/29  (DA-301)
-- parts -> partsupp -> suppliers. one row per part/supplier combo.
-- WIP left this half done, the address field sometimes has junk, clean later
--
-- 2022-02-17 b.osei
-- put the joins back in the where clause. i know. before anyone opens a
-- ticket: this shop moved off oracle in 2019 but the sourcing team still
-- reads these procs side by side with the old PL/SQL ones and they asked
-- for the two to look the same. there are no outer joins here so the
-- comma form is exactly the same query, the planner does not care.
-- if the fan-out FIXME below ever turns real this has to go back to
-- explicit joins first, because you cannot express a left join this way.
--
-- pg port: straight join, no snowflake-isms. create or replace table ->
-- drop + create.
-----------------------------------------------------------------------
create or replace procedure retail_datamart.build_part_suppliers()
language plpgsql
set search_path = retail_datamart, public
as
$$
begin
  drop table if exists retail_datamart.part_suppliers;
  create table retail_datamart.part_suppliers (
    part_supplier_key varchar(32),
    part_key          numeric(38,0),
    part_name         varchar,
    manufacturer      varchar,
    brand             varchar,
    part_type         varchar,
    part_size         numeric(38,0),
    container         varchar,
    retail_price      numeric(12,2),
    supplier_key      numeric(38,0),
    supplier_name     varchar,
    supplier_address  varchar,
    phone_number      varchar,
    account_balance   numeric(12,2),
    nation_key        numeric(38,0),
    available_quantity numeric(38,0),
    cost              numeric(12,2)
  );

  insert into retail_datamart.part_suppliers (
    part_supplier_key, part_key, part_name, manufacturer, brand, part_type,
    part_size, container, retail_price, supplier_key, supplier_name,
    supplier_address, phone_number, account_balance, nation_key,
    available_quantity, cost
  )
  select ps.part_supplier_key,
         p.part_key,
         p.name,
         p.manufacturer,
         p.brand,
         p.type,
         p.size,
         p.container,
         p.retail_price,
         s.supplier_key,
         s.supplier_name,
         s.supplier_address,
         s.phone_number,
         s.account_balance,
         s.nation_key,
         ps.available_quantity,
         ps.cost
    from stg_tpch_parts           p,
         stg_tpch_part_suppliers  ps,
         stg_tpch_suppliers       s
   where p.part_key      = ps.part_key
     and ps.supplier_key = s.supplier_key   -- FIXME might fan out if partsupp has 4 suppliers per part, verify
   order by p.part_key;

  -- select count(*) from part_suppliers; -- expected ~800k

  raise notice 'part_suppliers built';
end;
$$;
