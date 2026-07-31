/**********************************************************************
 * PROC    : BUILD_STG_TPCH_CUSTOMERS
 * AUTHOR  : G. WOZNIAK (DBA)
 * CREATED : 2018-11-04
 * PURPOSE : STAGE RAW CUSTOMER DATA. DO NOT TOUCH WITHOUT ASKING ME.
 * MODIFIED: 2019-02-12 GW - ADDED NAME SPLIT PER REQUEST FROM REPORTING.
 *                           THEY WANTED THE PREFIX AND THE ID SEPARATE.
 *                           FINE. DON'T COME BACK AND ASK FOR IT JOINED.
 * MODIFIED: 2020-07-19 GW - REPORTING ASKED WHY THE PLAN CHANGED. IT DID
 *                           NOT. I ADDED A SECOND WRAPPER SO THE FILTER
 *                           CANNOT GET PUSHED SOMEWHERE I DID NOT PUT IT.
 *                           THREE LAYERS. LEAVE THEM. ALL THREE.
 * PG PORT : converted from Snowflake SQL stored proc to PL/pgSQL.
 *           - CREATE OR REPLACE TABLE -> DROP + CREATE
 *           - RETURNS STRING / RETURN -> RAISE NOTICE
 *           - source RAW.TPCH_SF001.CUSTOMER -> public.customer
 *           - char(n) source cols are trimmed on the way into varchar
 *             by Postgres' assignment cast (verified), so NAME etc come
 *             through clean with no trailing padding.
 **********************************************************************/
CREATE OR REPLACE PROCEDURE retail_datamart.build_stg_tpch_customers()
LANGUAGE plpgsql
SET search_path = retail_datamart, public
AS
$$
DECLARE
	N_ROWS   BIGINT := 0;
	N_BLANK  BIGINT := 0;   -- 2019-02-12: COUNTS BLANK PREFIXES. NEVER FIRES. KEPT.
BEGIN

	/* DROP AND REBUILD. FULL RELOAD EVERY RUN -- IT IS SMALL ENOUGH. */
	DROP TABLE IF EXISTS retail_datamart.stg_tpch_customers;
	CREATE TABLE retail_datamart.stg_tpch_customers (
	      customer_key        numeric(38,0)
	    , name                varchar
	    , name_prefix         varchar
	    , name_id             varchar
	    , address             varchar
	    , nation_key          numeric(38,0)
	    , phone_number        varchar
	    , account_balance     numeric(12,2)
	    , market_segment      varchar
	    , comment             varchar
	);

	INSERT INTO retail_datamart.stg_tpch_customers
	/* NO COLUMN LIST. THE SELECT BELOW IS IN TABLE ORDER. IF YOU REORDER
	   THE TABLE YOU REORDER THE SELECT. THAT IS THE DEAL. -- GW         */
	SELECT * FROM (
	SELECT * FROM (
	SELECT * FROM (
		SELECT
		      c_custkey                    AS customer_key
		    , c_name                       AS name
		    , split_part(c_name, '#', 1)   AS name_prefix   -- EVERYTHING BEFORE THE HASH
		    , split_part(c_name, '#', 2)   AS name_id       -- THE NUMERIC TAIL
		    , c_address                    AS address
		    , c_nationkey                  AS nation_key
		    , c_phone                      AS phone_number
		    , c_acctbal                    AS account_balance
		--  , trim(c_phone)                AS phone_number  -- LEFT IN CASE THE DIRTY PHONE NUMBERS COME BACK
		    , c_mktsegment                 AS market_segment
		    , c_comment                    AS comment
		FROM public.customer
		WHERE 1 = 1                                         -- ANCHOR. DO NOT REMOVE.
	) AS L1
	) AS L2 WHERE 1 = 1
	) AS L3;

	GET DIAGNOSTICS N_ROWS = ROW_COUNT;

	/* 2019-02-12: SANITY. IF THIS EVER PRINTS, REPORTING BROKE THE FEED. */
	SELECT count(*) INTO N_BLANK
	  FROM retail_datamart.stg_tpch_customers
	 WHERE name_prefix IS NULL OR name_prefix = '';
	IF N_BLANK > 0 THEN
		RAISE WARNING 'STG_TPCH_CUSTOMERS: % ROWS WITH NO NAME PREFIX', N_BLANK;
	END IF;

	RAISE NOTICE 'stg_tpch_customers built';

END;
$$;
