/* ===========================================================
   order_items  --  dmitri k  2021/04/05
   #DA-502  flatten line items to one row per item
   money fields use decimal(16,3) per the money macro, leave it
   temparary fix, revisit the discount math when finance replies

   pg port: the snowflake select chained a LOT of lateral alias refs --
   base_price fed discounted_price, gross_item_sales_amount + item_discount
   fed item_tax_amount, which fed net_item_sales_amount, etc. postgres does
   not allow referencing an output alias from a sibling expression, so the
   single flat SELECT is unrolled into layered CTEs (calc1..calc3) where each
   layer can see the previous layer's computed columns. the arithmetic and
   the decimal(16,3) casts are unchanged, so the numbers come out identical.

   -----------------------------------------------------------
   2026-07-31  #DA-1147  incremental load
   -----------------------------------------------------------
   This used to DROP + CREATE the whole 6M row table on every run. It now
   loads incrementally off an order_date high-water mark and MERGEs on the
   order_item_key grain.

     call build_order_items();                  -- normal incremental run
     call build_order_items(true);              -- forced full refresh
     call build_order_items(false, 14);         -- widen the lookback window

   Safeguards, and why each one is here:

     1. ADVISORY LOCK. Two overlapping runs would both read the same
        watermark and merge the same window. pg_try_advisory_xact_lock
        makes the second one fail fast instead of interleaving. It is a
        transaction-scoped lock, so it is released even if we blow up.

     2. NO DROP. The table is created only if it is missing. An incremental
        model that drops its own target on every run is not incremental,
        and a mid-run failure would leave reporting with no table at all.
        Full refresh uses TRUNCATE, which keeps grants and indexes.

     3. UNIQUE INDEX ON order_item_key. This is what makes the MERGE
        deterministic and the whole proc re-runnable. If the grain is ever
        violated upstream the index raises instead of silently fanning out.

     4. LOOKBACK WINDOW. We do not trust max(order_date) as an exact
        boundary -- line items can land after their order date has already
        been loaded. We rewind p_lookback_days (default 3) behind the
        watermark and reprocess that window every run. The MERGE makes
        reprocessing free of side effects.

     5. EMPTY SOURCE ABORT. If staging is empty (upstream proc failed, or
        somebody is mid-rebuild) we raise instead of truncating a good
        table or "successfully" loading nothing.

     6. MERGE, NOT INSERT. Re-running the same window can never duplicate
        rows. The WHEN MATCHED arm also has an IS DISTINCT FROM guard so
        unchanged rows in the lookback window are not rewritten.

     7. ROW COUNTS. Inserted / updated counts are reported so a run that
        quietly did nothing is visible in the log.

   KNOWN LIMIT: an incremental load cannot see hard deletes, and it cannot
   see restatements older than the lookback window. If line items get
   backdated or purged, run with p_full_refresh => true.
   =========================================================== */
-- the pre-DA-1147 version of this proc took no arguments. it has to go, or
-- the defaults below make a bare call build_order_items() ambiguous.
drop procedure if exists retail_datamart.build_order_items();

create or replace procedure retail_datamart.build_order_items(
    p_full_refresh  boolean default false,
    p_lookback_days integer default 3
)
language plpgsql
set search_path = retail_datamart, public
as
$$
declare
  -- stable lock id for this table; any other session running this proc
  -- hashes to the same number and bounces off safeguard #1
  c_lock_key  constant bigint := hashtext('retail_datamart.order_items')::bigint;

  v_watermark date;
  v_cutoff    date;
  v_src_rows  bigint;
  v_before    bigint;
  v_after     bigint;
  v_touched   bigint;
  v_inserted  bigint;
  v_updated   bigint;
  v_seeding   boolean;
begin
  -- ---- safeguard #1: one loader at a time ----------------------------
  if not pg_try_advisory_xact_lock(c_lock_key) then
    raise exception 'build_order_items: another load is already running (lock %)', c_lock_key
      using hint = 'wait for it to finish, or check for a stuck session in pg_stat_activity';
  end if;

  if p_lookback_days is null or p_lookback_days < 0 then
    raise exception 'build_order_items: p_lookback_days must be >= 0, got %', p_lookback_days;
  end if;

  -- ---- safeguard #2: create, never drop ------------------------------
  create table if not exists retail_datamart.order_items (
    order_item_key        varchar(32),
    order_key             numeric(38,0),
    customer_key          numeric(38,0),
    part_key              numeric(38,0),
    supplier_key          numeric(38,0),
    order_date            date,
    order_status_code     varchar,
    is_return             boolean,
    line_number           numeric(38,0),
    order_item_status_code varchar,
    ship_date             date,
    commit_date           date,
    receipt_date          date,
    ship_mode             varchar,
    extended_price        numeric(12,2),
    quantity              numeric(38,2),
    base_price            decimal(16,3),
    discount_percentage   numeric(12,2),
    discounted_price      decimal(16,3),
    gross_item_sales_amount decimal(16,3),
    discounted_item_sales_amount decimal(16,3),
    item_discount_amount  decimal(16,3),
    tax_rate              numeric(12,2),
    item_tax_amount       decimal(16,3),
    net_item_sales_amount decimal(16,3),
    dw_loaded_at          timestamptz default now()   -- audit, added by DA-1147
  );

  -- older builds of this table predate the audit column. deliberately
  -- nullable with a plain DEFAULT: a NOT NULL + volatile default would
  -- force a full rewrite of 6M rows just to backfill now().
  alter table retail_datamart.order_items
    add column if not exists dw_loaded_at timestamptz;
  alter table retail_datamart.order_items
    alter column dw_loaded_at set default now();

  -- ---- safeguard #3: the grain is enforced, not assumed ---------------
  -- this is also the index the MERGE probes on. it will fail loudly if a
  -- previous full-refresh build left duplicate order_item_keys behind.
  create unique index if not exists order_items_pk
    on retail_datamart.order_items (order_item_key);

  -- watermark lookups scan this
  create index if not exists order_items_order_date_ix
    on retail_datamart.order_items (order_date);

  -- ---- safeguard #5: refuse to run against empty staging --------------
  -- checked before the truncate below, so a failed upstream proc can never
  -- turn into an empty order_items table.
  select count(*) into v_src_rows
  from (select 1 from retail_datamart.stg_tpch_line_items limit 1) probe;

  if v_src_rows = 0 then
    raise exception 'build_order_items: stg_tpch_line_items is empty, refusing to load'
      using hint = 'run build_stg_tpch_line_items first';
  end if;

  select count(*) into v_src_rows
  from (select 1 from retail_datamart.stg_tpch_orders limit 1) probe;

  if v_src_rows = 0 then
    raise exception 'build_order_items: stg_tpch_orders is empty, refusing to load'
      using hint = 'run build_stg_tpch_orders first';
  end if;

  -- ---- full refresh: truncate, do NOT drop ----------------------------
  if p_full_refresh then
    raise notice 'order_items: full refresh requested, truncating';
    truncate table retail_datamart.order_items;
  end if;

  select count(*) into v_before from retail_datamart.order_items;
  v_seeding := (v_before = 0);

  -- ---- safeguard #4: watermark minus lookback -------------------------
  if v_seeding then
    v_watermark := null;
    v_cutoff    := null;    -- null cutoff = no filter = load everything
    raise notice 'order_items: target is empty, seeding full history';
  else
    select max(order_date) into v_watermark from retail_datamart.order_items;
    v_cutoff := v_watermark - p_lookback_days;   -- date - int = date
    raise notice 'order_items: watermark %, reloading from % (% day lookback)',
                 v_watermark, v_cutoff, p_lookback_days;
  end if;

  -- ---- safeguard #6: upsert on the grain ------------------------------
  -- the calc1..calc3 CTE chain below is unchanged from the original port;
  -- only the WHERE on order_date and the surrounding MERGE are new.
  merge into retail_datamart.order_items tgt
  using (
    with base as (
      select
        line_item.order_item_key,
        orders.order_key,
        orders.customer_key,
        line_item.part_key,
        line_item.supplier_key,
        orders.order_date,
        orders.status_code as order_status_code,
        line_item.is_return,
        line_item.line_number,
        line_item.status_code as order_item_status_code,
        line_item.ship_date,
        line_item.commit_date,
        line_item.receipt_date,
        line_item.ship_mode,
        line_item.extended_price,
        line_item.quantity,
        line_item.discount_percentage,
        line_item.tax_rate
      from stg_tpch_orders orders
      inner join stg_tpch_line_items line_item
        on orders.order_key = line_item.order_key
      -- incremental predicate. v_cutoff is null on a seed run, and a null
      -- comparison would filter everything out, hence the explicit guard.
      where v_cutoff is null
         or orders.order_date >= v_cutoff
    ),

    -- layer 1: base_price needs extended_price/quantity (both passthrough)
    calc1 as (
      select
        base.*,
        -- extended_price is the line item total so back out price per item
        (extended_price / nullif(quantity, 0))::decimal(16,3) as base_price
      from base
    ),

    -- layer 2: things that depend on base_price / extended_price / discount
    calc2 as (
      select
        calc1.*,
        (base_price * (1 - discount_percentage))::decimal(16,3)      as discounted_price,
        extended_price                                               as gross_item_sales_amount,
        (extended_price * (1 - discount_percentage))::decimal(16,3)  as discounted_item_sales_amount,
        -- discounts are negative amounts (the -1)
        (-1 * extended_price * discount_percentage)::decimal(16,3)   as item_discount_amount
      from calc1
    ),

    -- layer 3: tax depends on gross + discount from layer 2
    calc3 as (
      select
        calc2.*,
        ((gross_item_sales_amount + item_discount_amount) * tax_rate)::decimal(16,3) as item_tax_amount
      from calc2
    )

    select
      order_item_key,
      order_key,
      customer_key,
      part_key,
      supplier_key,
      order_date,
      order_status_code,
      is_return,
      line_number,
      order_item_status_code,
      ship_date,
      commit_date,
      receipt_date,
      ship_mode,
      extended_price,
      quantity,
      base_price,
      discount_percentage,
      discounted_price,
      gross_item_sales_amount,
      discounted_item_sales_amount,
      item_discount_amount,
      tax_rate,
      item_tax_amount,
      -- this calcualtion has to net out, do not reorder
      (gross_item_sales_amount + item_discount_amount + item_tax_amount)::decimal(16,3) as net_item_sales_amount
    from calc3
  ) src
  on tgt.order_item_key = src.order_item_key

  -- most of the lookback window is unchanged every run. only rewrite a row
  -- if something actually moved, otherwise we churn the table for nothing.
  when matched and (
        tgt.order_key, tgt.customer_key, tgt.part_key, tgt.supplier_key,
        tgt.order_date, tgt.order_status_code, tgt.is_return, tgt.line_number,
        tgt.order_item_status_code, tgt.ship_date, tgt.commit_date,
        tgt.receipt_date, tgt.ship_mode, tgt.extended_price, tgt.quantity,
        tgt.base_price, tgt.discount_percentage, tgt.discounted_price,
        tgt.gross_item_sales_amount, tgt.discounted_item_sales_amount,
        tgt.item_discount_amount, tgt.tax_rate, tgt.item_tax_amount,
        tgt.net_item_sales_amount
      ) is distinct from (
        src.order_key, src.customer_key, src.part_key, src.supplier_key,
        src.order_date, src.order_status_code, src.is_return, src.line_number,
        src.order_item_status_code, src.ship_date, src.commit_date,
        src.receipt_date, src.ship_mode, src.extended_price, src.quantity,
        src.base_price, src.discount_percentage, src.discounted_price,
        src.gross_item_sales_amount, src.discounted_item_sales_amount,
        src.item_discount_amount, src.tax_rate, src.item_tax_amount,
        src.net_item_sales_amount
      )
  then update set
    -- target columns must stay UNQUALIFIED here, postgres rejects tgt.col
    order_key                    = src.order_key,
    customer_key                 = src.customer_key,
    part_key                     = src.part_key,
    supplier_key                 = src.supplier_key,
    order_date                   = src.order_date,
    order_status_code            = src.order_status_code,
    is_return                    = src.is_return,
    line_number                  = src.line_number,
    order_item_status_code       = src.order_item_status_code,
    ship_date                    = src.ship_date,
    commit_date                  = src.commit_date,
    receipt_date                 = src.receipt_date,
    ship_mode                    = src.ship_mode,
    extended_price               = src.extended_price,
    quantity                     = src.quantity,
    base_price                   = src.base_price,
    discount_percentage          = src.discount_percentage,
    discounted_price             = src.discounted_price,
    gross_item_sales_amount      = src.gross_item_sales_amount,
    discounted_item_sales_amount = src.discounted_item_sales_amount,
    item_discount_amount         = src.item_discount_amount,
    tax_rate                     = src.tax_rate,
    item_tax_amount              = src.item_tax_amount,
    net_item_sales_amount        = src.net_item_sales_amount,
    dw_loaded_at                 = now()

  when not matched then insert (
    order_item_key, order_key, customer_key, part_key, supplier_key,
    order_date, order_status_code, is_return, line_number, order_item_status_code,
    ship_date, commit_date, receipt_date, ship_mode, extended_price, quantity,
    base_price, discount_percentage, discounted_price, gross_item_sales_amount,
    discounted_item_sales_amount, item_discount_amount, tax_rate, item_tax_amount,
    net_item_sales_amount, dw_loaded_at
  ) values (
    src.order_item_key, src.order_key, src.customer_key, src.part_key, src.supplier_key,
    src.order_date, src.order_status_code, src.is_return, src.line_number, src.order_item_status_code,
    src.ship_date, src.commit_date, src.receipt_date, src.ship_mode, src.extended_price, src.quantity,
    src.base_price, src.discount_percentage, src.discounted_price, src.gross_item_sales_amount,
    src.discounted_item_sales_amount, src.item_discount_amount, src.tax_rate, src.item_tax_amount,
    src.net_item_sales_amount, now()
  );

  get diagnostics v_touched = row_count;

  -- ---- safeguard #7: say what actually happened -----------------------
  select count(*) into v_after from retail_datamart.order_items;
  v_inserted := v_after - v_before;
  v_updated  := v_touched - v_inserted;

  if v_seeding then
    -- fresh table, the planner has no stats for it yet and the next
    -- incremental run has to probe order_items_pk
    analyze retail_datamart.order_items;
  end if;

  raise notice 'order_items: % rows in target (% inserted, % updated by this run)',
               v_after, v_inserted, v_updated;
  raise notice 'order_items built (incremental, full_refresh=%)', p_full_refresh;
end;
$$;
