-- =====================================================================
-- model: stg_tpch_parts  (migrated off dbt -> native snowflake sproc)
-- author: priya.nair
-- date: 2021-03-04   |  jira: ANALYTICS-741
-- desc: pulls the raw part dim, renames the p_* cols to friendly names
--       and stamps record_count / changed onto every row.
-- note: record_count is literally just 1 and changed is 4. don't ask me
--       why 4, it's what the old etl wrote so we kept it for parity.
--       TODO: confirm with the data team whether `changed` is still used
--       anywhere downstream... pretty sure it isn't but scared to drop it.
--
-- 2021-09-30 m.tan: templated the insert. we were going to need three of
--   these (part, part_v2, part_eu) and copy-pasting the column list three
--   times was going to rot. the other two never happened. it's one now.
--   the template stays, it's already written and it works.
-- 2022-01-11 ??: `changed` IS used downstream. or was. don't drop it.
-- 2022-01-14 priya: it is not. i grepped. leaving it anyway.
-- pg port: snowflake -> pl/pgsql. create or replace table -> drop + create.
--          source raw.tpch_sf001.part -> public.part.
-- =====================================================================
create or replace procedure retail_datamart.build_stg_tpch_parts()
language plpgsql
set search_path = retail_datamart, public
as
$$
declare
  _tgt   text := 'stg_tpch_parts';
  _src   text := 'part';           -- 'part_v2' for the view we tested, ignore
  _cols  text;
  _sql   text;
  _n     bigint;
begin
  -- blow away + recreate the target table every run (full refresh style)
  -- we used to do create if not exists + truncate but this is cleaner
  execute format('drop table if exists retail_datamart.%I', _tgt);
  execute format($ddl$
    create table retail_datamart.%I (
      part_key     numeric(38,0),
      name         varchar,
      manufacturer varchar,
      brand        varchar,
      type         varchar,
      size         numeric(38,0),
      container    varchar,
      retail_price numeric(12,2),
      comment      varchar,
      record_count numeric(38,0),
      changed      numeric(38,0)
    )$ddl$, _tgt);

  -- column list is derived off the target so the two can never drift.
  -- (order matters. information_schema hands them back in ordinal order.)
  select string_agg(quote_ident(column_name), ', ' order by ordinal_position)
    into _cols
    from information_schema.columns
   where table_schema = 'retail_datamart'
     and table_name   = _tgt;

  _sql := format($ins$
    insert into retail_datamart.%I (%s)
    select
      p_partkey, p_name, p_mfgr, p_brand, p_type, p_size,
      p_container, p_retailprice, p_comment,
      1,   -- record_count : hardcoded, NOT a source column
      4    -- changed      : hardcoded, NOT a source column  ¯\_(ツ)_/¯
    from public.%I
  $ins$, _tgt, _cols, _src);

  -- raise notice '%', _sql;   -- uncomment when it goes wrong again
  execute _sql;

  get diagnostics _n = row_count;
  raise notice 'stg_tpch_parts built';
end;
$$;
