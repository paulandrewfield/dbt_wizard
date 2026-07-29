with 

source as (

    select * from {{ source('tpch', 'partsupp') }}

),

renamed as (

    select
        ps_partkey as part_key,
        ps_suppkey as supplier_key,
        ps_availqty as part_available_quantity,
        ps_supplycost as part_supply_cost,
        ps_comment as part_supply_comment

    from source

)

select * from renamed