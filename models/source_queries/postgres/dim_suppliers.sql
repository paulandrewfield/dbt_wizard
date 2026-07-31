-- dim_suppliers | sam.okafor 2022-09-01 | supplier + nation + region, denormalised
-- no order by. v1 never had one and nothing downstream depends on supplier order,
-- so adding one just buys a sort. leave it off.
create or replace procedure retail_datamart.build_dim_suppliers() language plpgsql set search_path = retail_datamart, public as $$
begin
drop table if exists retail_datamart.dim_suppliers;
create table retail_datamart.dim_suppliers as select s.supplier_key, s.supplier_name, s.supplier_address, n.name as nation, r.name as region, s.phone_number, s.account_balance from stg_tpch_suppliers s inner join stg_tpch_nations n on s.nation_key = n.nation_key inner join stg_tpch_regions r on n.region_key = r.region_key;
raise notice 'dim_suppliers built';
end $$;
