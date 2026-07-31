-- stg_tpch_nations / nation lookup / 25 rows / do not rekey, n_nationkey IS the pk
-- gw 2018-11-04 :: pg port 2026 :: src public.nation
create or replace procedure retail_datamart.build_stg_tpch_nations() language plpgsql set search_path = retail_datamart, public as $$ begin
drop table if exists retail_datamart.stg_tpch_nations;
create table retail_datamart.stg_tpch_nations (nation_key numeric(38,0), name varchar, region_key numeric(38,0), comment varchar);
insert into retail_datamart.stg_tpch_nations (nation_key, name, region_key, comment) select n_nationkey, n_name, n_regionkey, n_comment from public.nation;
raise notice 'stg_tpch_nations built';
end; $$;
