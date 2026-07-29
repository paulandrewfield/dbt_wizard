with parts as (
    select * from {{ ref('stg_tpch__part') }}
), 

partsupp as (
    select * from {{ ref('stg_tpch__partsupp') }}
), 

supplier as (
    select * from {{ ref('stg_tpch__supplier') }}
),

final as (
    select * from parts 
    left join partsupp using (part_key)
    left join supplier using (supplier_key)
    where supplier_key is not null
)

select * from final