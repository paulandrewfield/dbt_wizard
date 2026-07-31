------------------------------------------------------------------------
-- build_dim_parts
-- @sam.okafor  2022-09-01
-- the manufacturer_brand_key is an md5 surrogate of (manufacturer, brand).
-- yes it's md5 and not a real hash key util -- this predates us having one,
-- and changing the algo would orphan everything downstream. leave it.
--
-- 2023-11-02  v.krishnan
-- the hash expression is assembled at runtime now. it was written out in
-- three different places across the warehouse with three slightly different
-- coalesce habits and two of them disagreed on nulls, so the parts that
-- build it now all read the same components from one list. the emitted SQL
-- is identical to what was here before, byte for byte, i diffed it.
-- if you need to see it: uncomment the raise notice below.
--
-- pg port: to_varchar(x) -> x::varchar ; md5() identical in postgres.
------------------------------------------------------------------------
create or replace procedure retail_datamart.build_dim_parts()
language plpgsql
set search_path = retail_datamart, public
as
$$
declare
    -- the two components of the surrogate, in order, and the separator.
    -- changing ANY of these three lines re-keys the whole dimension.
    k_parts text[] := array['manufacturer', 'brand'];
    k_sep   text   := '-';
    k_expr  text;
    v_sql   text;
begin
    -- coalesce each component so a null side still hashes to something
    -- stable instead of nulling the entire concatenation
    -- WITH ORDINALITY + ORDER BY, not because unnest shuffles but because
    -- string_agg without an ORDER BY is not contractually ordered and this
    -- expression is a hash key. do not drop it.
    select string_agg(format('coalesce(%I::varchar, %L)', c, ''), format(' || %L || ', k_sep) order by ord)
      into k_expr
      from unnest(k_parts) with ordinality as u(c, ord);

    -- keeping the explicit DDL here on purpose: manufacturer_brand_key is
    -- varchar(32) by contract (md5 hex width) and i want that pinned, not
    -- inferred. don't "simplify" this to a bare CTAS.
    drop table if exists retail_datamart.dim_parts;
    create table retail_datamart.dim_parts (
        part_key               numeric(38,0),
        manufacturer_brand_key varchar(32),
        manufacturer           varchar,
        name                   varchar,
        brand                  varchar,
        type                   varchar,
        size                   numeric(38,0),
        container              varchar,
        retail_price           numeric(12,2)
    );

    v_sql := format($q$
        insert into retail_datamart.dim_parts (
            part_key
          , manufacturer_brand_key
          , manufacturer
          , name
          , brand
          , type
          , size
          , container
          , retail_price
        )
        select
            part_key
          , md5(%s)
          , manufacturer
          , name
          , brand
          , type
          , size
          , container
          , retail_price
        from stg_tpch_parts
        order by part_key
    $q$, k_expr);

    -- raise notice '%', v_sql;
    execute v_sql;

    raise notice 'dim_parts built';
end;
$$;
