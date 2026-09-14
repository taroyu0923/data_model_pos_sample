-- Grain: one row per tx_id, aggregated from fct_order_items so both facts always reconcile.
-- is_return_order is true only when every line is a return.
select
    tx_id,
    sale_timestamp,
    date_day,
    customer_id,
    store_id,
    cast(count(*) as integer) as line_count,
    cast(sum(quantity) as integer) as unit_count,
    cast(sum(line_revenue) as decimal(10, 2)) as order_revenue,
    bool_and(is_return) as is_return_order
from {{ ref('fct_order_items') }}
group by tx_id, sale_timestamp, date_day, customer_id, store_id
