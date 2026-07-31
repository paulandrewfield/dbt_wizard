-- #####################################################################
-- build_fct_tpch_parts  (finance mart - supplier/part reference)
-- owner: rwilson@      reviewed: m.tan
-- created 2022-12-06 | last touched 2023-05-19
-- ticket: FIN-2244  "supplier + part flat table for sourcing/cost lookups"
-- ref Confluence: Finance Data > Supplier Cost Mapping (v2)
-- finance request: exclude steel parts from this view (procurement handles those separately)
-- pg port: concat() works in postgres (numeric args auto-cast to text);
--          ilike is native postgres. no other snowflake-isms here.
-- #####################################################################
-- 2023-05-19  l.moreau (equipe Montreal / FIN-2244 suivi)
--   ATTENTION -- le filtre steel est applique APRES le case. c'est voulu.
--   part_material vaut 'brass' pour les types en ...BRASS, sinon c'est le
--   type brut. donc un type genre 'ECONOMY BRUSHED STEEL' passe par le
--   else, garde sa valeur brute, et se fait sortir par le not ilike.
--   si vous remontez le filtre avant le case vous filtrez sur autre chose.
--   les part_material NULL restent (jointure gauche sans correspondance) --
--   c'est expres, finance veut les voir pour les tracer.
-- #####################################################################
create or replace procedure retail_datamart.build_fct_tpch_parts()
language plpgsql
set search_path = retail_datamart, public
as
$$
begin
    drop table if exists retail_datamart.fct_tpch_parts;
    create table retail_datamart.fct_tpch_parts (
        supplier_key             numeric(38,0),
        nation_key               numeric(38,0),
        supplier_name            varchar,
        supplier_address         varchar,
        supplier_phone_number    varchar,
        supplier_account_balance numeric(12,2),
        supplier_comment         varchar,
        part_key                 numeric(38,0),
        part_name                varchar,
        part_manufacturer        varchar,
        part_brand               varchar,
        part_type                varchar,
        part_container           varchar,
        part_retail_price        numeric(12,2),
        part_comment             varchar,
        part_supplier_key        varchar(32),
        part_supplier_sk         varchar,
        part_supplier_available_qty numeric(38,0),
        part_supplier_cost       numeric(12,2),
        part_supplier_comment    varchar,
        part_material            varchar
    );

    insert into retail_datamart.fct_tpch_parts (
        supplier_key, nation_key, supplier_name, supplier_address,
        supplier_phone_number, supplier_account_balance, supplier_comment,
        part_key, part_name, part_manufacturer, part_brand, part_type,
        part_container, part_retail_price, part_comment, part_supplier_key,
        part_supplier_sk, part_supplier_available_qty, part_supplier_cost,
        part_supplier_comment, part_material
    )
    select j.* from (
    select
        s.supplier_key, s.nation_key, s.supplier_name, s.supplier_address,
        s.phone_number, s.account_balance, s.comment,
        pt.part_key, pt.name, pt.manufacturer, pt.brand, pt.type,
        pt.container, pt.retail_price, pt.comment,
        pps.part_supplier_key,
        concat(s.supplier_key, pt.part_key),      -- sk maison, pas un hash
        pps.available_quantity, pps.cost, pps.comment,
        -- FIN-2244 : on ecrase les types "...BRASS" en 'brass', le reste passe tel quel
        case when pt.type ilike '%BRASS' then 'brass' else pt.type end
    from stg_tpch_suppliers s
    left outer join stg_tpch_part_suppliers pps on s.supplier_key = pps.supplier_key
    left outer join stg_tpch_parts pt           on pt.part_key    = pps.part_key
    ) j (
        supplier_key, nation_key, supplier_name, supplier_address,
        supplier_phone_number, supplier_account_balance, supplier_comment,
        part_key, part_name, part_manufacturer, part_brand, part_type,
        part_container, part_retail_price, part_comment, part_supplier_key,
        part_supplier_sk, part_supplier_available_qty, part_supplier_cost,
        part_supplier_comment, part_material
    )
    -- voir l'entete : NULL = non mappe, on les garde
    where j.part_material is null
       or j.part_material not ilike '%steel%';

    raise notice 'fct_tpch_parts built';
end;
$$;
