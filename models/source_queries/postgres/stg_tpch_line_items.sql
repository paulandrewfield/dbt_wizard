-- stg_tpch_line_items
-- orig priya.nair 2021-06-18 ANALYTICS-882
-- 2022-06-02 k.iversen  ANALYTICS-1330  reworked the flag decode
-- 2023-02-19 k.iversen  no functional change, tidied
--
-- cleans raw lineitem. renames. derives the return flags.
-- skey = md5(orderkey || '-' || linenumber), same as the old dbt one.
--
-- the decode used to be two sibling CASEs that said the same thing twice.
-- snowflake let is_return point at the return_flag alias; postgres will
-- not (no lateral alias refs, it errors with "column does not exist").
-- so it is one CASE now, inside the other. one place to change it.
-- 'accepted' (l_returnflag = 'A') is the only non-return. everything
-- else including unknown is a return. do not "fix" that, it is on purpose.
--
-- insert column list is NOT in table order. it is in the order the select
-- was already in and i was not renumbering 18 columns by hand. the list
-- and the select line up, that is all that matters. -- ki
create or replace procedure retail_datamart.build_stg_tpch_line_items()
language plpgsql
set search_path = retail_datamart, public
as
$$
begin
	drop table if exists retail_datamart.stg_tpch_line_items;
	create table retail_datamart.stg_tpch_line_items (
	  order_item_key      varchar(32),   -- md5 surrogate, see header
	  order_key           numeric(38,0),
	  part_key            numeric(38,0),
	  supplier_key        numeric(38,0),
	  line_number         numeric(38,0),
	  quantity            numeric(38,2),
	  extended_price      numeric(12,2),
	  discount_percentage numeric(12,2),
	  tax_rate            numeric(12,2),
	  return_flag         varchar,
	  is_return           boolean,
	  status_code         varchar,
	  ship_date           date,
	  commit_date         date,
	  receipt_date        date,
	  ship_instructions   varchar,
	  ship_mode           varchar,
	  comment             varchar
	);

	insert into retail_datamart.stg_tpch_line_items
		( order_key, part_key, supplier_key, line_number
		, ship_date, commit_date, receipt_date
		, ship_instructions, ship_mode, comment
		, quantity, extended_price, discount_percentage, tax_rate
		, order_item_key
		, return_flag, is_return, status_code )
	select
		  li.l_orderkey
		, li.l_partkey
		, li.l_suppkey
		, li.l_linenumber
		, li.l_shipdate
		, li.l_commitdate
		, li.l_receiptdate
		, li.l_shipinstruct
		, li.l_shipmode
		, li.l_comment
		, li.l_quantity
		, li.l_extendedprice
		, li.l_discount        -- source is a rate 0-1. name is legacy. leave it.
		, li.l_tax
		-- grain = one row per (order, line). hash those two.
		, md5(coalesce(li.l_orderkey::varchar,'')||'-'||coalesce(li.l_linenumber::varchar,''))
		, dec.rf
		, case dec.rf when 'accepted' then false else true end
		, case li.l_linestatus
			when 'P' then 'returned'   -- P/F/O are the raw sf001 values
			when 'F' then 'billed'
			when 'O' then 'shipped'
			else null
		  end
	from public.lineitem li
	cross join lateral (
		select case
			when li.l_returnflag in ('R') then 'returned'
			when li.l_returnflag in ('A') then 'accepted'
			else 'unknown'
		end as rf
	) dec;

	raise notice 'stg_tpch_line_items built';
end;
$$;
