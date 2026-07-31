CREATE OR REPLACE PROCEDURE sp_load_all_staging_tables()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
DECLARE
    -- Array-like table structure listing source and target matches
    table_cursor CURSOR FOR 
        SELECT column1 AS src, column2 AS tgt FROM VALUES
        ('LINEITEM', 'STG_LINEITEM'),
        ('ORDERS', 'STG_ORDERS'),
        ('PARTSUPP', 'STG_PARTSUPP'),
        ('PART', 'STG_PART'),
        ('SUPPLIER', 'STG_SUPPLIER'),
        ('CUSTOMER', 'STG_CUSTOMER');
    query VARCHAR;
BEGIN
    FOR record IN table_cursor DO
        -- 1. Truncate staging table
        query := 'TRUNCATE TABLE ' || record.tgt;
        EXECUTE IMMEDIATE :query;
        
        -- 2. Bulk insert from sample data source
        query := 'INSERT INTO ' || record.tgt || ' SELECT * FROM SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.' || record.src;
        EXECUTE IMMEDIATE :query;
    END FOR;

    RETURN 'SUCCESS: All 6 staging tables truncated and loaded.';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'FAILED: ' || SQLERRM;
END;
$$;