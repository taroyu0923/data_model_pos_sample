-- Total signed quantity parsed straight from the raw items_sold strings must equal the line fact.
with bronze as (
    select sum(list_sum(list_transform(
        regexp_extract_all(items_sold, '(-?\d+)\s*[xX]\s', 1), lambda q: cast(q as integer)
    ))) as qty
    from {{ ref('brz_pos_system') }}
),

gold as (
    select sum(quantity) as qty from {{ ref('fct_order_items') }}
)

select bronze.qty as bronze_qty, gold.qty as gold_qty
from bronze, gold
where bronze.qty is distinct from gold.qty
