-- order_fraction per transaction sums to 1 (tolerance for DECIMAL(10,4) rounding, e.g. 3 x 0.3333).
select
    tx_id,
    sum(order_fraction) as total_fraction
from {{ ref('fct_order_items') }}
group by tx_id
having abs(sum(order_fraction) - 1) > 0.001
