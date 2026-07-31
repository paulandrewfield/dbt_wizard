--
-- region
-- 5 rows
-- five
-- do not index it
-- gw
--
create
or
replace
procedure
retail_datamart.build_stg_tpch_regions()
language
plpgsql
set
search_path
=
retail_datamart,
public
as
$$
begin

drop
table
if
exists
retail_datamart.stg_tpch_regions
;

create
table
retail_datamart.stg_tpch_regions
(
region_key
numeric(38,0)
,
name
varchar
,
comment
varchar
)
;

insert
into
retail_datamart.stg_tpch_regions
(
region_key
,
name
,
comment
)
select
r_regionkey
,
r_name
,
r_comment
from
public.region
;

raise
notice
'stg_tpch_regions built'
;

end
;
$$
;
