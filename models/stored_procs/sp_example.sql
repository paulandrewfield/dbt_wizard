{{ config(enabled=false) }}

-- Stored procedure definition kept in-repo but disabled as a dbt model.
-- Refactored to build the final table in a single pass.

CREATE OR REPLACE PROCEDURE ANALYTICS.dbt_ehunt.UpdateSuppliersPartsOrders()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN

CREATE OR REPLACE TABLE fct_tpch_parts AS
WITH supplier_parts AS (
    SELECT
        suppliers.s_suppkey AS supplier_id,
        suppliers.s_nationkey AS nation_id,
        parts.p_partkey AS part_id,
        CONCAT(suppliers.s_suppkey, parts.p_partkey) AS part_supplier_sk,
        suppliers.s_nationkey AS supplier_nation,
        part_suppliers.ps_availqty AS part_supplier_available_qty,
        part_suppliers.ps_supplycost AS part_supplier_cost,
        part_suppliers.ps_comment AS part_supplier_comment,
        suppliers.s_name AS supplier_name,
        suppliers.s_address AS supplier_address,
        suppliers.s_phone AS supplier_phone_number,
        suppliers.s_acctbal AS supplier_account_balance,
        suppliers.s_comment AS supplier_comment,
        parts.p_name AS part_name,
        parts.p_mfgr AS part_manufacturer,
        parts.p_brand AS part_brand,
        parts.p_type AS part_type,
        parts.p_container AS part_container,
        parts.p_retailprice AS part_retail_price,
        CASE
            WHEN parts.p_type ILIKE '%BRASS' THEN 'brass'
            ELSE parts.p_type
        END AS part_material,
        parts.p_comment AS part_comment,
        MIN(part_suppliers.ps_supplycost) OVER (
            PARTITION BY suppliers.s_nationkey
        ) AS lowest_part_cost_in_region
    FROM raw.tpch_sf001.supplier AS suppliers
    LEFT JOIN raw.tpch_sf001.partsupp AS part_suppliers
        ON suppliers.s_suppkey = part_suppliers.ps_suppkey
    LEFT JOIN raw.tpch_sf001.part AS parts
        ON parts.p_partkey = part_suppliers.ps_partkey
),
filtered_supplier_parts AS (
    SELECT *
    FROM supplier_parts
    WHERE part_material NOT ILIKE '%steel%'
)
SELECT *
FROM filtered_supplier_parts;

RETURN 'Stored procedure executed successfully.';

END;
$$;
