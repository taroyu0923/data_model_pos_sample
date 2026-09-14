-- Grain: one row per (tx_id, item_code). Codes missing from the catalog map to UNKNOWN_ITEM.
-- quantity is signed (returns negative); order_fraction = 1 / number of lines in the transaction.
with orders as (
    select
        tx_id,
        sale_timestamp,
        case contact_type
            when 'guest' then '__guest__'
            when 'invalid' then '__unknown__'
            else customer_contact
        end as customer_id,
        store_id
    from {{ ref('stg_pos_orders') }}
),

lines as (
    select
        l.tx_id,
        coalesce(i.item_code, 'UNKNOWN_ITEM') as item_code,
        cast(sum(l.quantity) as integer) as quantity
    from {{ ref('stg_pos_order_items') }} as l
    left join {{ ref('dim_item') }} as i
        on l.item_code = i.item_code
    group by l.tx_id, coalesce(i.item_code, 'UNKNOWN_ITEM')
)

select
    l.tx_id,
    l.item_code,
    o.sale_timestamp,
    cast(o.sale_timestamp as date) as date_day,
    o.customer_id,
    o.store_id,
    l.quantity,
    l.quantity < 0 as is_return,
    i.unit_price,
    cast(l.quantity * i.unit_price as decimal(10, 2)) as line_revenue,
    cast(1.0 / count(*) over (partition by l.tx_id) as decimal(10, 4)) as order_fraction
from lines as l
inner join orders as o
    on l.tx_id = o.tx_id
inner join {{ ref('dim_item') }} as i
    on l.item_code = i.item_code
