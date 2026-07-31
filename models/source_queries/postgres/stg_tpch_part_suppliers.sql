/*+==========================================================================+
  |                                                                          |
  |   S T G _ T P C H _ P A R T _ S U P P L I E R S                          |
  |                                                                          |
  |   author .... priya.nair                                                 |
  |   date ...... 2021-04-12          jira ... ANALYTICS-769                 |
  |   grain ..... one row per (part, supplier)                               |
  |                                                                          |
  |   the partsupp bridge has a composite pk and every downstream join       |
  |   hated it, so we hash the two parts into one surrogate. coalesce to     |
  |   empty string on both sides, otherwise one null nukes the whole         |
  |   digest. dbt_utils.surrogate_key did the same thing. keep it.           |
  |                                                                          |
  |   2021-11-08 -- staged through a temp table now. the direct insert was   |
  |   holding the target locked for the whole read and the 07:00 dashboard   |
  |   refresh kept timing out behind it. build cold, then land it.           |
  |                                                                          |
  |   pg port ... to_varchar(x) -> x::varchar ; md5() is identical in        |
  |               postgres (same 32-char hex). source -> public.partsupp.    |
  |                                                                          |
  +==========================================================================+*/
create or replace procedure retail_datamart.build_stg_tpch_part_suppliers()
language plpgsql
set search_path = retail_datamart, public
as
$$
declare
  v_staged   bigint := 0;
  v_landed   bigint := 0;
  v_dupes    bigint := 0;
begin

  /*--- 1. build cold in a temp table -------------------------------------*/
  drop table if exists tmp_partsupp_stage;
  create temp table tmp_partsupp_stage on commit drop as
  select
         md5(coalesce(ps_partkey::varchar, '') || '-' || coalesce(ps_suppkey::varchar, '')) as part_supplier_key
       , ps_partkey    as part_key
       , ps_suppkey    as supplier_key
       , ps_availqty   as available_quantity
       , ps_supplycost as cost
       , ps_comment    as comment
    from public.partsupp;

  get diagnostics v_staged = row_count;

  /*--- 2. the surrogate has to actually be unique -------------------------*/
  select count(*) into v_dupes
    from ( select part_supplier_key
             from tmp_partsupp_stage
            group by part_supplier_key
           having count(*) > 1 ) d;

  if v_dupes > 0 then
    raise exception 'stg_tpch_part_suppliers: % duplicate part_supplier_key values', v_dupes;
  end if;

  /*--- 3. land it ---------------------------------------------------------*/
  drop table if exists retail_datamart.stg_tpch_part_suppliers;
  create table retail_datamart.stg_tpch_part_suppliers (
         part_supplier_key  varchar(32)     /* 32-char md5 hex digest */
       , part_key           numeric(38,0)
       , supplier_key       numeric(38,0)
       , available_quantity numeric(38,0)
       , cost               numeric(12,2)
       , comment            varchar
  );

  insert into retail_datamart.stg_tpch_part_suppliers
       ( part_supplier_key, part_key, supplier_key, available_quantity, cost, comment )
  select part_supplier_key, part_key, supplier_key, available_quantity, cost, comment
    from tmp_partsupp_stage;

  get diagnostics v_landed = row_count;

  /* old single-col version, kept for reference:
       md5(ps_partkey::varchar) as part_supplier_key,                        */

  if v_landed <> v_staged then
    raise exception 'stg_tpch_part_suppliers: staged % but landed %', v_staged, v_landed;
  end if;

  raise notice 'stg_tpch_part_suppliers built';
end;
$$;
