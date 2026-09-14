-- Net revenue recomputed from Silver (lines x catalog price, unknown codes at the UNKNOWN_ITEM price or 0)
-- must equal Gold net revenue. Independent of the Gold joins and aggregation.
with unknown_price as (
    select max(unit_price) as unit_price
    from {{ ref('stg_catalog') }}
    where item_code = 'UNKNOWN_ITEM'
),

silver as (
    select coalesce(sum(l.quantity * coalesce(c.unit_price, u.unit_price, 0)), 0) as revenue
    from {{ ref('stg_pos_order_items') }} as l
    left join {{ ref('stg_catalog') }} as c
        on l.item_code = c.item_code
    cross join unknown_price as u
),

gold as (
    select coalesce(sum(order_revenue), 0) as revenue
    from {{ ref('fct_orders') }}
)

select silver.revenue as silver_revenue, gold.revenue as gold_revenue
from silver, gold
where silver.revenue <> gold.revenue
