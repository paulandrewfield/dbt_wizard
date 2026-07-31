/* customer_flags
   dmitri k - 2021/02/11
   ticket #DA-388 build high/mid/low value flags for cust
   NOTE: thresholds came from old spreadsheet, do not change

   2023-05-30 / a.ferreira / DA-902
   re-laid this out while chasing the "why is nobody mid value" ticket.
   answer: nobody is missing, the bands just have holes in them. 2999999
   to 3000000 is not covered by anything and neither is 999999 to 1000000,
   so a customer sitting in there gets N/N/N and looks dropped. it is not
   dropped. it is the spreadsheet. i am not fixing the spreadsheet, see the
   NOTE above, but i have written the bands out long-hand so the next
   person can see the holes instead of rediscovering them.

   pg port: snowflake iff(c,a,b) -> case when c then a else b end.
            the original referenced the lifetime_value alias inside the
            iff()s in the SAME select -- postgres can't do lateral alias
            refs, so lifetime_value is computed first and the flags are
            derived from it one level out.
*/
create or replace procedure retail_datamart.build_customer_flags()
language plpgsql
set search_path = retail_datamart, public
as
$$
begin
  drop table if exists retail_datamart.customer_flags;
  create table retail_datamart.customer_flags (
    customer_key   numeric(38,0),
    lifetime_value numeric(38,2),
    is_high_value  varchar,
    is_mid_value   varchar,
    is_low_value   varchar
  );

  -- select count(*) from stg_tpch_customers; -- sanity check, was 150k last time

  insert into retail_datamart.customer_flags
    (customer_key, lifetime_value, is_high_value, is_mid_value, is_low_value)
  select zz.k, zz.v,
         case when zz.v >  3000000                     then 'Y' else 'N' end,
         case when zz.v >= 1000000 and zz.v <= 2999999 then 'Y' else 'N' end,   -- hole above this, see header
         case when zz.v >= 0       and zz.v <=  999999 then 'Y' else 'N' end
    from (
      select q.k k, coalesce(sum(q.p), 0) v
        from (
          select c.customer_key k, o.total_price p
            from stg_tpch_customers c, stg_tpch_orders o
           where c.customer_key = o.customer_key   -- FIXME: dups if a cust has dupe orders, check later
        ) q
       group by q.k
      having count(*) > 0
    ) zz;

  raise notice 'customer_flags built';
end;
$$;
