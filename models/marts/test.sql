{{
    config(
        materialized='view'
    )
}}

with order_items as (
    select * from {{ ref('order_items') }}
), 

part_suppliers as (
    select * from {{ ref('part_suppliers') }}
),

final as (
     select
     {{ dbt_utils.generate_surrogate_key(['o.order_key', 'o.supplier_key', 'o.part_key']) }} as fct_order_item_key,
    o.ORDER_DATE, year(o.ORDER_DATE) as order_year, o.ORDER_TIME, o.TOTAL_PRICE, o.LINE_NUMBER, o.LINE_QUANTITY_ORDERED, o.LINE_EXTENDED_PRICE, o.LINE_DISCOUNT, o.LINE_TAX,
    p.PART_RETAIL_PRICE, p.PART_AVAILABLE_QUANTITY*5 As part_available_quantity, 1 as test
     from order_items o
     left join part_suppliers p using (part_key, supplier_key)

    
)

select * from final
